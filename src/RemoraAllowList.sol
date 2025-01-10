// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @custom:security-contact support@remora.us
/**
 * @title Remora Allowlist
 * @notice This contract manages an allowlist of addresses that are permitted to interact with Remora RWA tokens.
 * It provides functionalities to add, remove, and check allowed addresses.
 * Access control and upgradeability are implemented using OpenZeppelin libraries.
 */
contract RemoraAllowlist is Initializable, AccessManagedUpgradeable, UUPSUpgradeable {
    /**
     * @dev Mapping that tracks the allowed status of addresses. 
     * An address is `true` if allowed, and `false` otherwise.
     */
    mapping(address => bool) private _allowed;

    /**
     * @dev Emitted when an address is added to the allowlist.
     * @param user The address that was allowed.
     */
    event UserAllowed(address indexed user);

    /**
     * @dev Emitted when an address is removed from the allowlist.
     * @param user The address that was disallowed.
     */
    event UserDisallowed(address indexed user);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

      /**
     * @notice Initializes the allowlist contract.
     * This function sets up the UUPS upgradeability pattern.
     * Can only be called once.
     */
    function initialize() initializer public {
        __UUPSUpgradeable_init();
    }

    /**
     * @notice Checks if an account is allowed to interact with Remora RWA tokens.
     * @param account The address to check.
     * @return A boolean indicating whether the account is allowed (`true`) or not (`false`).
     */
    function allowed(address account) public view returns (bool) {
       return _allowed[account];
    }

    /**
     * @notice Checks whether both the `from` and `to` addresses are allowed to interact with tokens.
     * @param from The address initiating the transfer.
     * @param to The address receiving the tokens.
     * @return The first disallowed address (`from` or `to`). Returns `address(0)` if both are allowed.
     */
    function exchangeAllowed(address from, address to) external view returns (address) {
        if(!_allowed[from]) return from;
        if(!_allowed[to]) return to;
        return address(0);
    }

    /**
     * @notice Adds a user to the allowlist, permitting them to interact with Remora RWA tokens.
     * This function is restricted to authorized accounts via AccessManaged.
     * @param user The address to allow.
     * @return A boolean indicating whether the user was already allowed (`true`) or not (`false`).
     * 
     * Emits a {UserAllowed} event if the user is newly allowed.
     */
    function allowUser(address user) external restricted returns (bool) {
        bool isAllowed = allowed(user);
        if (!isAllowed) {
            _allowed[user] = true;
            emit UserAllowed(user);
        }
        return isAllowed;
    }

    /**
     * @notice Removes a user from the allowlist, preventing them from interacting with Remora RWA tokens.
     * This function is restricted to authorized accounts via AccessManaged.
     * @param user The address to disallow.
     * @return A boolean indicating whether the user was already disallowed (`false`) or not (`true`).
     * 
     * Emits a {UserDisallowed} event if the user is newly disallowed.
     */
    function disallowUser(address user) external restricted returns (bool) {
        bool isAllowed = allowed(user);
        if (isAllowed) {
            _allowed[user] = false;
            emit UserDisallowed(user);
        }
        return isAllowed;
    }

    /**
     * @notice Authorizes the upgrade of the contract to a new implementation.
     * This function is restricted to authorized accounts via AccessManaged.
     * @param newImplementation The address of the new contract implementation.
     * 
     * Requirements:
     * - Can only be called by an authorized account.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        restricted
        override
    {}
}