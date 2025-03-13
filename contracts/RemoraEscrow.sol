// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

contract RemoraEscrow is
    Initializable,
    AccessManagedUpgradeable,
    UUPSUpgradeable
{
    mapping(address => mapping(uint8 => )) tokensSent;

    struct TransactionInfo {
      uint32 amount;
      uint32 timestamp;
      
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialAuthority) public initializer {
        __AccessManaged_init(initialAuthority);
        __UUPSUpgradeable_init();
    }





    function _authorizeUpgrade(
        address newImplementation
    ) internal override restricted {}
}
