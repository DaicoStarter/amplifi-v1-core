// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.19;

import {uUNIT} from "prb-math/UD60x18.sol";
import {IRegistrar} from "amplifi-v1-common/interfaces/IRegistrar.sol";
import {TokenInfo} from "amplifi-v1-common/models/TokenInfo.sol";
import {Addressable} from "amplifi-v1-common/utils/Addressable.sol";
import {Stewardable} from "amplifi-v1-common/utils/Stewardable.sol";

contract Registrar is IRegistrar, Addressable, Stewardable {
    address private s_bookkeeper;
    address private s_pud;
    address private s_treasurer;
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

    function setTokenInfo(address token, TokenInfo calldata tokenInfo) external requireSteward {
        require(tokenInfo.liquidationRatioDx18 < uUNIT, "Registrar: liquidation ratio must be [0, 1)");

        s_tokenInfos[token] = tokenInfo;
    }

    function getBookkeeper() external view returns (address bookkeeper) {
        return s_bookkeeper;
    }

    function getPUD() external view returns (address pud) {
        return s_pud;
    }

    function getTreasurer() external view returns (address treasurer) {
        return s_treasurer;
    }

    function getTokenInfoOf(address token) external view returns (TokenInfo memory tokenInfo) {
        return s_tokenInfos[token];
    }
}
