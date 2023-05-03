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
        require(_msgSender() == s_bookkeeper || _msgSender() == s_treasurer, "PUD: require bookkeeper or treasurer");
        _;
    }

    constructor(string memory name, string memory symbol, address registrar) ERC20(name, symbol) {
        s_REGISTRAR = IRegistrar(registrar);
        IRegistrar(registrar).setPUD(address(this));
    }

    function initialize() external {
        require(s_bookkeeper == address(0) && s_treasurer == address(0), "PUD: already initialized");

        IRegistrar registrar = s_REGISTRAR;
        s_bookkeeper = registrar.getBookkeeper();
        s_treasurer = registrar.getTreasurer();
    }

    function mint(uint256 amount) external requireBookkeeperOrTreasurer {
        _mint(_msgSender(), amount);
    }

    function burn(uint256 amount) external requireBookkeeperOrTreasurer {
        _burn(_msgSender(), amount);
    }
}
