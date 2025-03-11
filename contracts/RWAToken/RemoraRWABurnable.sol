// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @custom:security-contact support@remora.us
/**
 * @title RemoraRWABurnable
 * @dev A contract module that enables toggling of a burning mechanism for tokens.
 *      This module is meant to be used through inheritance, and it provides
 *      functionalities for managing the burning state, as well as burning tokens
 *      under certain conditions. It integrates with the Pausable and ERC20
 *      functionalities from OpenZeppelin.
 */
abstract contract RemoraRWABurnable is
    Initializable,
    ContextUpgradeable,
    ERC20Upgradeable
{
    /// @custom:storage-location erc7201:remora.storage.Burnable
    struct BurnableStorage {
        /// @dev Tracks whether the burning functionality is currently enabled.
        bool _burnable;
    }

    // keccak256(abi.encode(uint256(keccak256("remora.storage.Burnable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BurnableStorageLocation =
        0x2adc39c2ceb3679aceb50aaf215b36473ed254d0a4593ff456d46f15c4dd3b00;

    /// @notice Emitted when the burning state is changed.
    /// @param burnable The new state of the burning functionality (true = enabled, false = disabled).
    event BurningStateChanged(bool burnable);

    /// @notice Error thrown when a function requiring burning is called while burning is disabled.
    error BurningNotEnabled();

    /// @notice Error thrown when trying to enable burning while it is already enabled.
    error BurningAlreadyEnabled();

    /// @dev Modifier to enforce that burning is enabled before function execution.
    modifier whenBurnable() {
        _requireBurnable();
        _;
    }

    /**
     * @notice Checks the current burnable status.
     * @return `true` if burning is enabled, `false` otherwise.
     */
    function burnable() public view returns (bool) {
        BurnableStorage storage $ = _getBurnableStorage();
        return $._burnable;
    }

    /**
     * @notice Initializes the contract, setting the burning state to disabled.
     * @dev This function should only be called during contract initialization.
     */
    function __RemoraBurnable_init() internal onlyInitializing {
        __RemoraBurnable_init_unchained();
    }

    /**
     * @notice Internal function to initialize the burning state.
     * @dev Sets the `_burnable` state to `false`.
     */
    function __RemoraBurnable_init_unchained() internal onlyInitializing {
        BurnableStorage storage $ = _getBurnableStorage();
        $._burnable = false;
    }

    /**
     * @notice Enables the burning functionality.
     * @dev Reverts with `BurningAlreadyEnabled` if burning is already enabled.
     * Emits a `BurningStateChanged` event.
     */
    function _enableBurning() internal {
        if (burnable()) {
            revert BurningAlreadyEnabled();
        }
        BurnableStorage storage $ = _getBurnableStorage();
        $._burnable = true;
        emit BurningStateChanged(true);
    }

    /**
     * @notice Disables the burning functionality.
     * @dev Requires that burning is currently enabled.
     * Emits a `BurningStateChanged` event.
     */
    function _disableBurning() internal whenBurnable {
        BurnableStorage storage $ = _getBurnableStorage();
        $._burnable = false;
        emit BurningStateChanged(false);
    }

    /**
     * @notice Burns a specific amount of tokens from a given account, using allowance.
     * @param account The account from which tokens will be burned.
     * @param value The amount of tokens to be burned.
     * @dev Requires that burning is enabled and the contract is not paused.
     * Uses `_spendAllowance` and `_burn` functions from `ERC20Upgradeable`.
     */
    function _burnFrom(address account, uint256 value) internal whenBurnable {
        _spendAllowance(account, _msgSender(), value);
        _burn(account, value);
    }

    /**
     * @notice Ensures that burning is enabled before proceeding.
     * @dev Reverts with `BurningNotEnabled` if burning is disabled.
     */
    function _requireBurnable() internal view virtual {
        if (!burnable()) {
            revert BurningNotEnabled();
        }
    }

    /**
     * @dev Returns the storage slot for burnable state.
     * @return $ The BurnableStorage struct containing the burnable state.
     */
    function _getBurnableStorage()
        private
        pure
        returns (BurnableStorage storage $)
    {
        assembly {
            $.slot := BurnableStorageLocation
        }
    }
}
