// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.19;

import {mulDiv, mulDiv18} from "prb-math/common.sol";
import {uUNIT} from "prb-math/UD60x18.sol";
import {RepaymentMode} from "amplifi-v1-common/models/RepaymentMode.sol";
import {ArrayHelper} from "amplifi-v1-common/utils/ArrayHelper.sol";
import {Position} from "../models/Position.sol";

library PositionHelper {
    using ArrayHelper for address[];
    using ArrayHelper for uint256[];
    using PositionHelper for Position;

    function addFungible(Position storage s_self, address token, uint256 amount) internal {
        uint256 oldBalance = s_self.fungibleBalances[token];

        if (oldBalance == 0) {
            s_self.fungibles.push(token);
        }
        s_self.fungibleBalances[token] = oldBalance + amount;
    }

    function addNonFungible(Position storage s_self, address token, uint256 tokenId) internal {
        if (s_self.nonFungibleIds[token].length == 0) {
            s_self.nonFungibles.push(token);
        }
        s_self.nonFungibleIds[token].push(tokenId);
    }

    function addDebt(Position storage s_self, uint256 nominalAmount, uint256 interestCumulativeUDx18)
        internal
        returns (uint256 realAmount)
    {
        realAmount = mulDiv(nominalAmount, uUNIT, interestCumulativeUDx18);
        s_self.realDebt += realAmount;
        s_self.nominalDebt += nominalAmount;
    }

    function removeFungible(Position storage s_self, address token, uint256 amount) internal {
        uint256 newBalance = s_self.fungibleBalances[token] - amount;

        s_self.fungibleBalances[token] = newBalance;
        if (newBalance == 0) {
            s_self.fungibles.remove(token);
        }
    }

    function removeNonFungible(Position storage s_self, address token, uint256 tokenId) internal {
        s_self.nonFungibleIds[token].remove(tokenId);
        if (s_self.nonFungibleIds[token].length == 0) {
            s_self.nonFungibles.remove(token);
        }
    }

    function removeDebt(
        Position storage s_self,
        uint256 nominalAmount,
        uint256 interestCumulativeUDx18,
        RepaymentMode repaymentMode
    ) internal returns (uint256 realAmount, uint256 interestAmount) {
        uint256 realDebt = s_self.realDebt;
        uint256 nominalDebt = s_self.nominalDebt;
        uint256 effectiveDebt = s_self.getDebt(interestCumulativeUDx18);
        uint256 interest = effectiveDebt > nominalDebt ? effectiveDebt - nominalDebt : 0;
        require(nominalAmount <= effectiveDebt, "PositionHelper: excessive repayment");

        if (nominalAmount == effectiveDebt) {
            realAmount = realDebt;
            interestAmount = interest;
            s_self.realDebt = 0;
            s_self.nominalDebt = 0;
        } else {
            realAmount = mulDiv(nominalAmount, uUNIT, interestCumulativeUDx18);
            s_self.realDebt = realDebt - realAmount;

            if (repaymentMode == RepaymentMode.Proportional) {
                interestAmount = mulDiv(nominalAmount, interest, effectiveDebt);
                s_self.nominalDebt = nominalDebt - (nominalAmount - interestAmount);
            } else if (repaymentMode == RepaymentMode.InterestFirst) {
                if (nominalAmount > interest) {
                    interestAmount = interest;
                    s_self.nominalDebt = nominalDebt - (nominalAmount - interestAmount);
                } else {
                    interestAmount = nominalAmount;
                }
            } else if (repaymentMode == RepaymentMode.PrincipalFirst) {
                if (nominalAmount > nominalDebt) {
                    interestAmount = nominalAmount - nominalDebt;
                    s_self.nominalDebt = 0;
                } else {
                    s_self.nominalDebt = nominalDebt - nominalAmount;
                }
            } else {
                revert("PositionHelper: invalid repayment mode");
            }
        }
    }

    function getPrincipal(Position storage s_self) internal view returns (uint256 principal) {
        principal = s_self.nominalDebt;
    }

    function getDebt(Position storage s_self, uint256 interestCumulativeUDx18) internal view returns (uint256 debt) {
        debt = mulDiv18(s_self.realDebt, interestCumulativeUDx18);
    }

    function getFungibles(Position storage s_self)
        internal
        view
        returns (address[] memory tokens, uint256[] memory balances)
    {
        tokens = s_self.fungibles;
        balances = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = s_self.fungibleBalances[tokens[i]];
        }
    }

    function getNonFungibles(Position storage s_self)
        internal
        view
        returns (address[] memory tokens, uint256[] memory tokenIds)
    {
        uint256 size;
        address[] memory tokens_ = s_self.nonFungibles;

        for (uint256 i = 0; i < tokens_.length; i++) {
            size += s_self.nonFungibleIds[tokens_[i]].length;
        }

        tokens = new address[](size);
        tokenIds = new uint256[](size);
        size = 0;

        for (uint256 i = 0; i < tokens_.length; i++) {
            uint256[] memory tokenIds_ = s_self.nonFungibleIds[tokens_[i]];

            for (uint256 j = 0; i < tokenIds_.length; j++) {
                tokens[size] = tokens_[i];
                tokenIds[size++] = tokenIds_[j];
            }
        }
    }

    function hasAsset(Position storage s_self) internal view returns (bool hasAsset_) {
        hasAsset_ = s_self.fungibles.length > 0 || s_self.nonFungibles.length > 0;
    }

    function hasDebt(Position storage s_self) internal view returns (bool hasDebt_) {
        hasDebt_ = s_self.realDebt > 0;
    }
}
