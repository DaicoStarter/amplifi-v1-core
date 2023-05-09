// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ERC721Enumerable,
    ERC721,
    IERC721
} from "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {mulDiv18} from "prb-math/common.sol";
import {UD60x18, uUNIT, UNIT, add, mul, powu, wrap, unwrap} from "prb-math/UD60x18.sol";
import {IBookkeeper} from "amplifi-v1-common/interfaces/IBookkeeper.sol";
import {IPUD} from "amplifi-v1-common/interfaces/IPUD.sol";
import {IRegistrar} from "amplifi-v1-common/interfaces/IRegistrar.sol";
import {ITreasurer} from "amplifi-v1-common/interfaces/ITreasurer.sol";
import {IBorrowCallback} from "amplifi-v1-common/interfaces/callbacks/IBorrowCallback.sol";
import {ILiquidateCallback} from "amplifi-v1-common/interfaces/callbacks/ILiquidateCallback.sol";
import {IWithdrawFungibleCallback} from "amplifi-v1-common/interfaces/callbacks/IWithdrawFungibleCallback.sol";
import {IWithdrawFungiblesCallback} from "amplifi-v1-common/interfaces/callbacks/IWithdrawFungiblesCallback.sol";
import {IWithdrawNonFungibleCallback} from "amplifi-v1-common/interfaces/callbacks/IWithdrawNonFungibleCallback.sol";
import {RegressionMode} from "amplifi-v1-common/models/RegressionMode.sol";
import {TokenInfo, TokenType} from "amplifi-v1-common/models/TokenInfo.sol";
import {Addressable} from "amplifi-v1-common/utils/Addressable.sol";
import {Lockable} from "amplifi-v1-common/utils/Lockable.sol";
import {PositionHelper, Position} from "../utils/PositionHelper.sol";

contract Bookkeeper is IBookkeeper, Addressable, Lockable, ERC721Enumerable {
    using PositionHelper for Position;
    using SafeERC20 for IERC20;

    IRegistrar private immutable s_REGISTRAR;
    address private s_pud;
    address private s_treasurer;
    uint256 private s_lastBlockTimestamp;
    uint256 private s_interestCumulativeUDx18;

    uint256 private s_totalRealDebt;
    uint256 private s_lastPositionId;
    mapping(uint256 => Position) private s_positions;
    mapping(address => uint256) private s_totalFungibleBalances;
    mapping(address => mapping(uint256 => uint256)) private s_nonFungiblePositions;

    modifier requireToken(address token, TokenType type_) {
        TokenInfo memory tokenInfo = s_REGISTRAR.getTokenInfoOf(token);
        require(tokenInfo.enabled, "Bookkeeper: token is not enabled");
        require(tokenInfo.type_ == type_, "Bookkeeper: token is wrong type");
        _;
    }

    modifier requireTokens(address[] calldata tokens, TokenType type_) {
        for (uint256 i = 0; i < tokens.length; i++) {
            TokenInfo memory tokenInfo = s_REGISTRAR.getTokenInfoOf(tokens[i]);
            require(tokenInfo.enabled, "Bookkeeper: token is not enabled");
            require(tokenInfo.type_ == type_, "Bookkeeper: token is wrong type");
        }
        _;
    }

    modifier ensurePosition(uint256 positionId) {
        _updateInterestCumulative();
        _;
        uint256 debt = s_positions[positionId].getDebt(s_interestCumulativeUDx18);
        if (s_positions[positionId].fungibleBalances[s_pud] < debt) {
            (uint256 value, uint256 margin) = getAppraisalOf(positionId);
            require(value >= debt + margin, "Bookkeeper: insufficient equity to meet margin requirement");
        }
    }

    constructor(string memory name, string memory symbol, address registrar) ERC721(name, symbol) {
        s_REGISTRAR = IRegistrar(registrar);
        IRegistrar(registrar).setBookkeeper(address(this));
    }

    function initialize() external {
        require(s_pud == address(0) && s_treasurer == address(0), "Bookkeeper: already initialized");

        initializeLock();
        IRegistrar registrar = s_REGISTRAR;
        s_pud = registrar.getPUD();
        s_treasurer = registrar.getTreasurer();
        s_lastBlockTimestamp = block.timestamp;
        s_interestCumulativeUDx18 = uUNIT;
    }

    function mint(address originator, address recipient) external returns (uint256 positionId) {
        require(
            _msgSender() == recipient || isApprovedForAll(recipient, _msgSender()),
            "Bookkeeper: require owner or operator"
        );

        positionId = ++s_lastPositionId;
        _safeMint(recipient, positionId);
        s_positions[positionId].originator = originator;
    }

    function burn(uint256 positionId) external {
        address owner = ownerOf(positionId);
        require(_exists(positionId), "Bookkeeper: position does not exist");
        require(_msgSender() == owner || isApprovedForAll(owner, _msgSender()), "Bookkeeper: require owner or operator");

        Position storage s_position = s_positions[positionId];
        require(!s_position.hasAsset(), "Bookkeeper: cannot burn position with asset");
        require(!s_position.hasDebt(), "Bookkeeper: cannot burn position with debt");

        delete s_positions[positionId];
        _burn(positionId);
    }

    function depositFungible(uint256 positionId, address token)
        external
        requireToken(token, TokenType.Fungible)
        returns (uint256 amount)
    {
        require(_exists(positionId), "Bookkeeper: position does not exist");

        amount = _depositFungible(s_positions[positionId], token);

        emit DepositFungible(_msgSender(), positionId, token, amount);
    }

    function depositNonFungible(uint256 positionId, address token, uint256 item)
        external
        requireToken(token, TokenType.NonFungible)
    {
        require(_exists(positionId), "Bookkeeper: position does not exist");
        require(IERC721(token).ownerOf(item) == address(this), "Bookkeeper: non-fungible token deposit not received");
        require(s_nonFungiblePositions[token][item] == 0, "Bookkeeper: non-fungible token already deposited");

        s_positions[positionId].addNonFungible(token, item);
        s_nonFungiblePositions[token][item] = positionId;

        emit DepositNonFungible(_msgSender(), positionId, token, item);
    }

    function withdrawFungible(uint256 positionId, address token, uint256 amount, address recipient, bytes calldata data)
        external
        requireUnlocked
        requireToken(token, TokenType.Fungible)
        requireNonZeroAddress(recipient)
        ensurePosition(positionId)
        returns (bytes memory callbackResult)
    {
        address owner = ownerOf(positionId);
        require(_exists(positionId), "Bookkeeper: position does not exist");
        require(_msgSender() == owner || isApprovedForAll(owner, _msgSender()), "Bookkeeper: require owner or operator");

        _withdrawFungible(s_positions[positionId], token, amount);
        IERC20(token).safeTransfer(recipient, amount);
        if (Address.isContract(_msgSender())) {
            callbackResult = IWithdrawFungibleCallback(_msgSender()).withdrawFungibleCallback(
                positionId, token, amount, recipient, data
            );
        }

        emit WithdrawFungible(_msgSender(), positionId, token, amount, recipient);
    }

    function withdrawFungibles(
        uint256 positionId,
        address[] calldata tokens,
        uint256[] calldata amounts,
        address recipient,
        bytes calldata data
    )
        external
        requireUnlocked
        requireTokens(tokens, TokenType.Fungible)
        ensurePosition(positionId)
        returns (bytes memory callbackResult)
    {
        {
            address owner = ownerOf(positionId);
            require(_exists(positionId), "Bookkeeper: position does not exist");
            require(
                _msgSender() == owner || isApprovedForAll(owner, _msgSender()), "Bookkeeper: require owner or operator"
            );
            require(recipient != address(0), "Addressable: require non-zero address");
        }

        Position storage s_position = s_positions[positionId];
        require(tokens.length == amounts.length, "Bookkeeper: tokens and amounts have different length");

        for (uint256 i = 0; i < tokens.length; i++) {
            address fungible = tokens[i];
            uint256 amount = amounts[i];
            _withdrawFungible(s_position, fungible, amount);
            IERC20(fungible).safeTransfer(recipient, amount);
        }
        if (Address.isContract(_msgSender())) {
            callbackResult = IWithdrawFungiblesCallback(_msgSender()).withdrawFungiblesCallback(
                positionId, tokens, amounts, recipient, data
            );
        }

        emit WithdrawFungibles(_msgSender(), positionId, tokens, amounts, recipient);
    }

    function withdrawNonFungible(
        uint256 positionId,
        address token,
        uint256 item,
        address recipient,
        bytes calldata data
    )
        external
        requireUnlocked
        requireToken(token, TokenType.NonFungible)
        requireNonZeroAddress(recipient)
        ensurePosition(positionId)
        returns (bytes memory callbackResult)
    {
        address owner = ownerOf(positionId);
        require(_exists(positionId), "Bookkeeper: position does not exist");
        require(_msgSender() == owner || isApprovedForAll(owner, _msgSender()), "Bookkeeper: require owner or operator");

        _withdrawNonFungible(s_positions[positionId], token, item);
        IERC721(token).safeTransferFrom(address(this), recipient, item);
        if (Address.isContract(_msgSender())) {
            callbackResult = IWithdrawNonFungibleCallback(_msgSender()).withdrawNonFungibleCallback(
                positionId, token, item, recipient, data
            );
        }

        emit WithdrawNonFungible(_msgSender(), positionId, token, item, recipient);
    }

    function borrow(uint256 positionId, uint256 amount, bytes calldata data)
        external
        requireUnlocked
        ensurePosition(positionId)
    {
        address owner = ownerOf(positionId);
        require(_exists(positionId), "Bookkeeper: position does not exist");
        require(_msgSender() == owner || isApprovedForAll(owner, _msgSender()), "Bookkeeper: require owner or operator");

        address pud = s_pud;
        Position storage s_position = s_positions[positionId];
        require(amount > 0, "Bookkeeper: borrow amount must be greater than zero");

        IPUD(pud).mint(amount);
        s_totalRealDebt += s_position.addDebt(amount, s_interestCumulativeUDx18);
        require(_depositFungible(s_position, pud) == amount, "Bookkeeper: borrow failed");

        if (Address.isContract(_msgSender())) {
            IBorrowCallback(_msgSender()).borrowCallback(positionId, amount, data);
        }

        emit Borrow(_msgSender(), positionId, amount);
    }

    function repay(uint256 positionId, uint256 amount) external {
        address owner = ownerOf(positionId);
        require(_exists(positionId), "Bookkeeper: position does not exist");
        require(_msgSender() == owner || isApprovedForAll(owner, _msgSender()), "Bookkeeper: require owner or operator");

        _updateInterestCumulative();
        address pud = s_pud;
        Position storage s_position = s_positions[positionId];
        require(amount > 0, "Bookkeeper: repay amount must be greater than zero");

        _withdrawFungible(s_position, pud, amount);
        (uint256 realDebt, uint256 interest) =
            s_position.removeDebt(amount, s_interestCumulativeUDx18, s_REGISTRAR.getRepaymentMode());
        s_totalRealDebt -= realDebt;
        IPUD(pud).burn(amount - interest);

        if (interest > 0) {
            _allotInterest(interest, s_position.originator);
        }

        emit Repay(_msgSender(), positionId, amount - interest, interest);
    }

    function liquidate(uint256 positionId, address recipient, bytes calldata data) external {
        require(_exists(positionId), "Bookkeeper: position does not exist");
        require(recipient != address(0), "Addressable: require non-zero address");

        _updateInterestCumulative();
        address pud = s_pud;
        Position storage s_position = s_positions[positionId];
        uint256 debt = s_position.getDebt(s_interestCumulativeUDx18);
        uint256 value;
        {
            uint256 margin;
            (value, margin) = getAppraisalOf(positionId);
            require(value < debt + margin, "Bookkeeper: sufficient equity to meet margin requirement");
        }

        uint256 principal = s_position.getPrincipal();
        uint256 penalty = mulDiv18(debt, s_REGISTRAR.getPenaltyRate());
        {
            uint256 pudNeeded = value <= principal + penalty ? principal : value - penalty;
            uint256 pudBalance = s_position.fungibleBalances[pud];
            if (Address.isContract(_msgSender())) {
                ILiquidateCallback(_msgSender()).liquidateCallback(
                    positionId, pudNeeded > pudBalance ? pudNeeded - pudBalance : 0, data
                );
            }
            require(s_position.fungibleBalances[pud] >= pudNeeded, "Bookkeeper: insufficient PUD");

            _withdrawFungible(s_position, pud, pudNeeded);
        }
        IPUD(pud).burn(principal);

        if (value > principal + penalty) {
            _allotInterest(Math.min(value - principal - penalty, debt - principal), s_position.originator);

            if (value > debt + penalty) {
                IERC20(pud).safeTransfer(ownerOf(positionId), value - debt - penalty);
            }
        }

        _transferAssets(s_position, recipient);

        {
            (uint256 realDebt,) = s_position.removeDebt(debt, s_interestCumulativeUDx18, s_REGISTRAR.getRepaymentMode());
            s_totalRealDebt -= realDebt;
        }

        emit Liquidate(_msgSender(), positionId, principal, 0, penalty, 0, recipient); //TODO: interest & equity
    }

    function getTotalDebt() public view returns (uint256 totalDebt) {
        totalDebt = mulDiv18(s_totalRealDebt, _getInterestCumulative());
    }

    function getDebtOf(uint256 positionId) public view returns (uint256 debt) {
        debt = s_positions[positionId].getDebt(_getInterestCumulative());
    }

    function getAppraisalOf(uint256 positionId) public view returns (uint256 value, uint256 margin) {
        ITreasurer treasurer = ITreasurer(s_treasurer);
        (address[] memory fungibles, uint256[] memory balances) = getFungiblesOf(positionId);
        (uint256 fungiblesValue, uint256 fungiblesMargin) = treasurer.getAppraisalOfFungibles(fungibles, balances);
        (address[] memory nonFungibles, uint256[] memory items) = getNonFungiblesOf(positionId);
        (uint256 nonFungiblesValue, uint256 nonFungiblesMargine) =
            treasurer.getAppraisalOfNonFungibles(nonFungibles, items);

        value = fungiblesValue + nonFungiblesValue;
        margin = fungiblesMargin + nonFungiblesMargine;
    }

    function getFungiblesOf(uint256 positionId)
        public
        view
        returns (address[] memory tokens, uint256[] memory balances)
    {
        (tokens, balances) = s_positions[positionId].getFungibles();
    }

    function getNonFungiblesOf(uint256 positionId)
        public
        view
        returns (address[] memory tokens, uint256[] memory items)
    {
        (tokens, items) = s_positions[positionId].getNonFungibles();
    }

    function onERC721Received(address, /*operator*/ address, /*from*/ uint256, /*item*/ bytes calldata /*data*/ )
        external
        view
        requireToken(_msgSender(), TokenType.NonFungible)
        returns (bytes4 identifier)
    {
        identifier = this.onERC721Received.selector;
    }

    function _depositFungible(Position storage s_position, address token) private returns (uint256 amount) {
        uint256 totalBalance = s_totalFungibleBalances[token];
        amount = IERC20(token).balanceOf(address(this)) - totalBalance;
        require(amount > 0, "Bookkeeper: fungible token deposit not received");

        s_position.addFungible(token, amount);
        s_totalFungibleBalances[token] = totalBalance + amount;
    }

    function _withdrawFungible(Position storage s_position, address token, uint256 amount) private {
        s_position.removeFungible(token, amount);
        s_totalFungibleBalances[token] -= amount;
    }

    function _withdrawNonFungible(Position storage s_position, address token, uint256 item) private {
        s_position.removeNonFungible(token, item);
        delete s_nonFungiblePositions[token][item];
    }

    function _transferAssets(Position storage s_position, address recipient) private {
        uint256 fungiblesLength = s_position.fungibles.length;
        for (uint256 i = 0; i < fungiblesLength; i++) {
            address fungible = s_position.fungibles[0]; // always work on the first position as the array is being modified
            uint256 amount = s_position.fungibleBalances[fungible];
            _withdrawFungible(s_position, fungible, amount);
            IERC20(fungible).safeTransfer(recipient, amount);
        }

        uint256 nonFungiblesLength = s_position.nonFungibles.length;
        for (uint256 i = 0; i < nonFungiblesLength; i++) {
            address nonFungible = s_position.nonFungibles[0]; // always work on the first position as the array is being modified
            uint256 nonFungibleItemsLength = s_position.nonFungibleItems[nonFungible].length;
            for (uint256 j = 0; j < nonFungibleItemsLength; j++) {
                uint256 nonFungibleItem = s_position.nonFungibleItems[nonFungible][0];
                _withdrawNonFungible(s_position, nonFungible, nonFungibleItem); // always work on the first position as the array is being modified
                IERC721(nonFungible).safeTransferFrom(address(this), recipient, nonFungibleItem);
            }
        }
    }

    function _allotInterest(uint256 amount, address originator) private {
        address pud = s_pud;
        uint256 allotedAmount;
        (address[] memory addresses, uint256[] memory ratesUDx18) = s_REGISTRAR.getAllotmentRates();

        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] != address(0)) {
                uint256 proportion = mulDiv18(amount, ratesUDx18[i]);
                IERC20(pud).safeTransfer(addresses[i], proportion);
                allotedAmount += proportion;
            }
        }
        IERC20(pud).safeTransfer(originator, amount - allotedAmount);
    }

    function _updateInterestCumulative() private {
        uint256 timeElapsed = block.timestamp - s_lastBlockTimestamp;
        if (timeElapsed > 0) {
            s_interestCumulativeUDx18 = _calculateInterestCumulative(timeElapsed);
            s_lastBlockTimestamp = block.timestamp;
        }
    }

    function _getInterestCumulative() private view returns (uint256 interestCumulativeUDx18) {
        uint256 timeElapsed = block.timestamp - s_lastBlockTimestamp;

        interestCumulativeUDx18 =
            timeElapsed == 0 ? s_interestCumulativeUDx18 : _calculateInterestCumulative(timeElapsed);
    }

    function _calculateInterestCumulative(uint256 timeElapsed) private view returns (uint256 interestCumulativeUDx18) {
        IRegistrar registrar = s_REGISTRAR;
        UD60x18 effectiveRate;
        UD60x18 baseRate = wrap(registrar.getInterestRate());
        RegressionMode regressionMode = registrar.getRegressionMode();

        if (regressionMode == RegressionMode.None) {
            effectiveRate = add(UNIT, baseRate);
        } else {
            (uint256 accelerator,) = ITreasurer(s_treasurer).getAppraisalOfFungible(registrar.getPricePeg(), uUNIT);

            if (regressionMode == RegressionMode.Linear) {
                effectiveRate = add(UNIT, mul(baseRate, wrap(accelerator)));
            } else if (regressionMode == RegressionMode.Quadratic) {
                effectiveRate = add(UNIT, mul(baseRate, powu(wrap(accelerator), 2)));
            } else if (regressionMode == RegressionMode.Cubic) {
                effectiveRate = add(UNIT, mul(baseRate, powu(wrap(accelerator), 3)));
            } else {
                revert("Bookkeeper: invalid acceleration mode");
            }
        }

        interestCumulativeUDx18 = mulDiv18(s_interestCumulativeUDx18, unwrap(powu(effectiveRate, timeElapsed)));
    }
}
