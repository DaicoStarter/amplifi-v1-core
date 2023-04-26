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

    function addFungibleToken(Position storage s_self, address token, uint256 amount) internal {
        uint256 oldBalance = s_self.fungibleTokenBalances[token];

        if (oldBalance == 0) {
            s_self.fungibleTokens.push(token);
        }
        s_self.fungibleTokenBalances[token] = oldBalance + amount;
    }

    function addNonFungibleToken(Position storage s_self, address token, uint256 tokenId) internal {
        if (s_self.nonFungibleTokenIds[token].length == 0) {
            s_self.nonFungibleTokens.push(token);
        }
        s_self.nonFungibleTokenIds[token].push(tokenId);
    }

    function addDebt(Position storage s_self, uint256 nominalAmount, uint256 interestCumulativeUDx18)
        internal
        returns (uint256 realAmount)
    {
        realAmount = mulDiv(nominalAmount, uUNIT, interestCumulativeUDx18);
        s_self.realDebt += realAmount;
        s_self.nominalDebt += nominalAmount;
    }

    function removeFungibleToken(Position storage s_self, address token, uint256 amount) internal {
        uint256 newBalance = s_self.fungibleTokenBalances[token] - amount;

        s_self.fungibleTokenBalances[token] = newBalance;
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

    function removeDebt(
        Position storage s_self,
        uint256 nominalAmount,
        uint256 interestCumulativeUDx18,
        RepaymentMode repaymentMode
    ) internal returns (uint256 realAmount, uint256 interestAmount) {
        uint256 realDebt = s_self.realDebt;
        uint256 nominalDebt = s_self.nominalDebt;
        uint256 effectiveDebt = mulDiv18(s_self.realDebt, interestCumulativeUDx18);
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
}
