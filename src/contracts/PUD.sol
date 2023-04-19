// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.19;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IPUD} from "amplifi-v1-common/interfaces/IPUD.sol";
import {IRegistrar} from "amplifi-v1-common/interfaces/IRegistrar.sol";

contract PUD is IPUD, ERC20 {
    IRegistrar private immutable s_REGISTRAR;
    address private s_bookkeeper;
    address private s_treasurer;

    modifier requireBookkeeperOrTreasurer() {
        require(msg.sender == s_bookkeeper || msg.sender == s_treasurer, "PUD: require bookkeeper or treasurer");
        _;
    }

    constructor(string memory name, string memory symbol, address registrar) ERC20(name, symbol) {
        s_REGISTRAR = IRegistrar(registrar);
        s_REGISTRAR.setPUD(address(this));
    }

    function initialize() external {
        require(s_bookkeeper == address(0) && s_treasurer == address(0), "PUD: already initialized");

        s_bookkeeper = s_REGISTRAR.getBookkeeper();
        s_treasurer = s_REGISTRAR.getTreasurer();
    }

    function mint(uint256 amount) external requireBookkeeperOrTreasurer {
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) external requireBookkeeperOrTreasurer {
        _burn(msg.sender, amount);
    }
}
