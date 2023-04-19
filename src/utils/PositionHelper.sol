// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.19;

import {ArrayHelper} from "amplifi-v1-common/utils/ArrayHelper.sol";
import {Position} from "../models/Position.sol";

library PositionHelper {
    using ArrayHelper for address[];
    using ArrayHelper for uint256[];

    function addFungibleToken(Position storage s_self, address token, uint256 amount) internal {
        uint256 oldBalance = s_self.fungibleBalances[token];

        if (oldBalance == 0) {
            s_self.fungibleTokens.push(token);
        }
        s_self.fungibleBalances[token] = oldBalance + amount;
    }

    function addNonFungibleToken(Position storage s_self, address token, uint256 tokenId) internal {
        if (s_self.nonFungibleTokenIds[token].length == 0) {
            s_self.nonFungibleTokens.push(token);
        }
        s_self.nonFungibleTokenIds[token].push(tokenId);
    }

    function removeFungibleToken(Position storage s_self, address token, uint256 amount) internal {
        uint256 newBalance = s_self.fungibleBalances[token] - amount;

        s_self.fungibleBalances[token] = newBalance;
        if (newBalance == 0) {
            s_self.fungibleTokens.remove(token);
        }
    }

    function removeNonFungibleToken(Position storage s_self, address token, uint256 tokenId) internal {
        s_self.nonFungibleTokenIds[token].remove(tokenId);
        if (s_self.nonFungibleTokenIds[token].length == 0) {
            s_self.nonFungibleTokens.remove(token);
        }
    }
}
