// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.19;

import {uUNIT} from "prb-math/UD60x18.sol";
import {IRegistrar} from "amplifi-v1-common/interfaces/IRegistrar.sol";
import {AccelerationMode} from "amplifi-v1-common/models/AccelerationMode.sol";
import {RepaymentMode} from "amplifi-v1-common/models/RepaymentMode.sol";
import {TokenInfo} from "amplifi-v1-common/models/TokenInfo.sol";
import {Addressable} from "amplifi-v1-common/utils/Addressable.sol";
import {Stewardable} from "amplifi-v1-common/utils/Stewardable.sol";

contract Registrar is IRegistrar, Addressable, Stewardable {
    address private s_bookkeeper;
    address private s_pud;
    address private s_treasurer;
    uint256 private s_interestRateUDx18;
    uint256 private s_penaltyRateUDx18;
    address[] private s_distributionAddresses;
    uint256[] private s_distributionRatesUDx18;
    AccelerationMode private s_accelerationMode;
    RepaymentMode private s_repaymentMode;
    mapping(address => TokenInfo) private s_tokenInfos;

    constructor(address steward) Stewardable(steward) {}

    function setBookkeeper(address bookkeeper) external requireSender(bookkeeper) requireZeroAddress(s_bookkeeper) {
        s_bookkeeper = bookkeeper;
    }

    function setPUD(address pud) external requireSender(pud) requireZeroAddress(s_pud) {
        s_pud = pud;
    }

    function setTreasurer(address treasurer) external requireSender(treasurer) requireZeroAddress(s_treasurer) {
        s_treasurer = treasurer;
    }

    function setInterestRate(uint256 interestRateUDx18) external requireSteward {
        s_interestRateUDx18 = interestRateUDx18;
    }

    function setPenaltyRate(uint256 penaltyRateUDx18) external requireSteward {
        s_penaltyRateUDx18 = penaltyRateUDx18;
    }

    function setDistributionRates(address[] calldata distributionAddresses, uint256[] calldata distributionRatesUDx18)
        external
        requireSteward
    {
        require(
            distributionAddresses.length == distributionRatesUDx18.length,
            "Registrar: addresses and rates are different in length"
        );
        uint256 totalDistributionRateUDx18;
        for (uint256 i = 0; i < distributionRatesUDx18.length; i++) {
            totalDistributionRateUDx18 += distributionRatesUDx18[i];
        }
        require(totalDistributionRateUDx18 == uUNIT, "Registrar: distribution rates must add up to 1");

        s_distributionAddresses = distributionAddresses;
        s_distributionRatesUDx18 = distributionRatesUDx18;
    }

    function setAccelerationMode(AccelerationMode accelerationMode) external requireSteward {
        s_accelerationMode = accelerationMode;
    }

    function setRepaymentMode(RepaymentMode repaymentMode) external requireSteward {
        s_repaymentMode = repaymentMode;
    }

    function setTokenInfo(address token, TokenInfo calldata tokenInfo) external requireSteward {
        require(tokenInfo.liquidationRatioUDx18 < uUNIT, "Registrar: liquidation ratio must be [0, 1)");

        s_tokenInfos[token] = tokenInfo;
    }

    function getBookkeeper() external view returns (address bookkeeper) {
        bookkeeper = s_bookkeeper;
    }

    function getPUD() external view returns (address pud) {
        pud = s_pud;
    }

    function getTreasurer() external view returns (address treasurer) {
        treasurer = s_treasurer;
    }

    function getInterestRate() external view returns (uint256 interestRateUDx18) {
        interestRateUDx18 = s_interestRateUDx18;
    }

    function getPenaltyRate() external view returns (uint256 penaltyRateUDx18) {
        penaltyRateUDx18 = s_penaltyRateUDx18;
    }

    function getDistributionRates()
        external
        view
        returns (address[] memory distributionAddresses, uint256[] memory distributionRatesUDx18)
    {
        distributionAddresses = s_distributionAddresses;
        distributionRatesUDx18 = s_distributionRatesUDx18;
    }

    function getAccelerationMode() external view returns (AccelerationMode accelerationMode) {
        accelerationMode = s_accelerationMode;
    }

    function getRepaymentMode() external view returns (RepaymentMode repaymentMode) {
        repaymentMode = s_repaymentMode;
    }

    function getTokenInfoOf(address token) external view returns (TokenInfo memory tokenInfo) {
        tokenInfo = s_tokenInfos[token];
    }
}
