// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.19;

import {uUNIT} from "prb-math/UD60x18.sol";
import {IRegistrar} from "amplifi-v1-common/interfaces/IRegistrar.sol";
import {RegressionMode} from "amplifi-v1-common/models/RegressionMode.sol";
import {RepaymentMode} from "amplifi-v1-common/models/RepaymentMode.sol";
import {TokenInfo} from "amplifi-v1-common/models/TokenInfo.sol";
import {Addressable} from "amplifi-v1-common/utils/Addressable.sol";
import {Stewardable} from "amplifi-v1-common/utils/Stewardable.sol";

contract Registrar is IRegistrar, Addressable, Stewardable {
    address private immutable s_PRICE_PEG;
    address private s_bookkeeper;
    address private s_pud;
    address private s_treasurer;
    uint256 private s_interestRateUDx18;
    uint256 private s_penaltyRateUDx18;
    address[] private s_allotmentAddresses;
    uint256[] private s_allotmentRatesUDx18;
    RegressionMode private s_regressionMode;
    RepaymentMode private s_repaymentMode;
    mapping(address => TokenInfo) private s_tokenInfos;

    constructor(address steward, address pricePeg) Stewardable(steward) {
        s_PRICE_PEG = pricePeg;
    }

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

    function setAllotmentRates(address[] calldata allotmentAddresses, uint256[] calldata allotmentRatesUDx18)
        external
        requireSteward
    {
        require(
            allotmentAddresses.length == allotmentRatesUDx18.length,
            "Registrar: addresses and rates have different length"
        );
        uint256 totalAllotmentRateUDx18;
        for (uint256 i = 0; i < allotmentRatesUDx18.length; i++) {
            totalAllotmentRateUDx18 += allotmentRatesUDx18[i];
        }
        require(totalAllotmentRateUDx18 == uUNIT, "Registrar: allotment rates must add up to 1");

        s_allotmentAddresses = allotmentAddresses;
        s_allotmentRatesUDx18 = allotmentRatesUDx18;
    }

    function setRegressionMode(RegressionMode regressionMode) external requireSteward {
        s_regressionMode = regressionMode;
    }

    function setRepaymentMode(RepaymentMode repaymentMode) external requireSteward {
        s_repaymentMode = repaymentMode;
    }

    function setTokenInfo(address token, TokenInfo calldata tokenInfo) external requireSteward {
        require(tokenInfo.marginRatioUDx18 < uUNIT, "Registrar: margin ratio must be [0, 1)");

        s_tokenInfos[token] = tokenInfo;
    }

    function getPricePeg() external view returns (address pricePeg) {
        pricePeg = s_PRICE_PEG;
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

    function getAllotmentRates()
        external
        view
        returns (address[] memory allotmentAddresses, uint256[] memory allotmentRatesUDx18)
    {
        allotmentAddresses = s_allotmentAddresses;
        allotmentRatesUDx18 = s_allotmentRatesUDx18;
    }

    function getRegressionMode() external view returns (RegressionMode regressionMode) {
        regressionMode = s_regressionMode;
    }

    function getRepaymentMode() external view returns (RepaymentMode repaymentMode) {
        repaymentMode = s_repaymentMode;
    }

    function getTokenInfoOf(address token) external view returns (TokenInfo memory tokenInfo) {
        tokenInfo = s_tokenInfos[token];
    }
}
