// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract Stablecoin is ERC20, ERC20Permit {
    uint8 _numDecimals;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        uint8 numDecimals
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        _numDecimals = numDecimals;
        _mint(msg.sender, _initialSupply * 10 ** decimals());
    }

    function decimals() public view override returns (uint8) {
        return _numDecimals;
    }
}
