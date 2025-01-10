// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/manager/AccessManagerUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @custom:security-contact support@remora.us
contract RemoraManager is Initializable, AccessManagerUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    uint64 public constant OPERATIONS = 1; // handles pausing, minting, burning
    uint64 public constant UPGRADER = 2; // handles upgrading, changing values in contracts.
    uint64 public constant FACILITATOR = 3; // hanldes transfering, swapping, rent distribution.

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialAdmin) initializer public override {
        __AccessManager_init(initialAdmin);
        __Ownable_init(initialAdmin);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}
}