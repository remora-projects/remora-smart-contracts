// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {AccessManagerUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagerUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @custom:security-contact support@remora.us
/**
 * @title RemoraManager
 * @notice Created to add restricted upgradeable functionality to access manager.
 */
contract RemoraManagerV2 is
    Initializable,
    UUPSUpgradeable,
    AccessManagerUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function version() external pure returns (uint256) {
        return 2;
    }

    /**
     * @notice initializer function for upgradeable contract.
     * @param initialAdmin Address of owner and initial admin of Access Manager.
     */
    function initialize(address initialAdmin) public override initializer {
        __AccessManager_init(initialAdmin);
        __UUPSUpgradeable_init();
    }

    /**
     * @dev override required by solidity, need to create upgrader role to call this function
     * @param newImplementation Address of the new implementation to be upgraded to.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal view override {
        require(address(this) == msg.sender);
    }
}
