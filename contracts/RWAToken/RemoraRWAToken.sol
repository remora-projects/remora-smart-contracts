// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {RemoraRWABurnable} from "./RemoraRWABurnable.sol";
import {RemoraRWAHolderManagement} from "./RemoraRWAHolderManagement.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface Allowlist {
    function exchangeAllowed(address, address) external view;
}

/// @custom:security-contact support@remora.us
/**
 * @title RemoraRWAToken
 * @notice This contract represents a Real-World Asset (RWA) token, allowing tokenized representation of physical assets.
 * It incorporates features for managing transfers, minting, burning, allowlist checks, payouts, allowance permitting, and pausing.
 * The token operates with OpenZeppelin upgradeable contracts and custom modules for RWA-specific operations.
 */
contract RemoraRWAToken is
    Initializable,
    ERC20PermitUpgradeable,
    PausableUpgradeable,
    RemoraRWABurnable,
    RemoraRWAHolderManagement,
    UUPSUpgradeable
{
    /// @dev Reference to the external allowlist contract for managing user permissions.
    Allowlist private _allowlist;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the RWA token contract with specified parameters.
     * @param tokenOwner The initial owner of the tokens, must be on allowList.
     * @param initialAuthority The address granted initial access management authority.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     * @param _initialSupply The initial supply of tokens, in whole units.
     * @param allowList The address of the allowlist contract.
     * @param stablecoin The address of the stablecoin used for payouts.
     * @param wallet The address of the wallet to withdraw contract funds.
     * @param feePercentage The fee percentage for payouts.
     */
    function initialize(
        address tokenOwner,
        address initialAuthority,
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        address allowList,
        address stablecoin,
        address wallet,
        uint256 feePercentage
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __Pausable_init();
        __RemoraBurnable_init();
        __RemoraHolderManagement_init(
            initialAuthority,
            stablecoin,
            wallet,
            feePercentage
        );
        __UUPSUpgradeable_init();

        _allowlist = Allowlist(allowList);

        _mint(tokenOwner, _initialSupply * 10 ** decimals());
    }

    /**
     * @notice Allows token holders to claim rent when conditions allow.
     * @dev Enforces stablecoin payout with fee set in holder management.
     */
    function claimRent() external whenNotPaused nonReentrant {
        _claimRent(_msgSender(), true, false, 0);
    }

    /**
     * @notice Function that allows restricted accounts to change the way pay out is collected.
     * @param investor Address of the investor collecting payout.
     * @param useStablecoin Value indicating whether to pay out in stablecoin or not.
     * @param useCustomFee Value indicating whether or not to use a custom fee.
     * @param feeValue The custom fee to use if useCustomFee is true.
     */
    function adminClaimRent(
        address investor,
        bool useStablecoin,
        bool useCustomFee,
        uint256 feeValue
    ) external restricted nonReentrant {
        _claimRent(investor, useStablecoin, useCustomFee, feeValue);
    }

    /**
     * @notice Allows restricted accounts to transfer tokens without pausing, freezing, or allowlist restrictions.
     * @dev Calls OpenZeppelin ERC20Upgradeable transferFrom function.
     * @param from The address from which tokens are being transferred.
     * @param to The recipient address.
     * @param value The number of tokens to transfer.
     * @return A boolean indicating whether the transfer succeeded.
     */
    function adminTransferFrom(
        address from,
        address to,
        uint256 value
    ) external restricted returns (bool) {
        return super.transferFrom(from, to, value);
    }

    /**
     * @notice Updates the address of the allowlist contract. Restricted to authorized accounts.
     * @param newImplementation The new allowlist contract address.
     */
    function updateAllowList(address newImplementation) external restricted {
        require(newImplementation != address(0));
        _allowlist = Allowlist(newImplementation);
    }

    /**
     * @notice Mints new tokens. Restricted to authorized accounts.
     * @param to The recipient address.
     * @param amount The number of tokens to mint.
     */
    function mint(address to, uint256 amount) external restricted {
        _mint(to, amount);
    }

    /**
     * @notice Pauses all token transfers, burning, and rent collection. Restricted to authorized accounts.
     */
    function pause() external restricted {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers, burning, and rent collection. Restricted to authorized accounts.
     */
    function unpause() external restricted {
        _unpause();
    }

    /**
     * @notice Enables the burning of tokens. Restricted to authorized accounts.
     */
    function enableBurning() external restricted {
        _enableBurning();
    }

    /**
     * @notice Disables the burning of tokens. Restricted to authorized accounts.
     */
    function disableBurning() external restricted {
        _disableBurning();
    }

    /**
     * @notice Transfers tokens to a recipient if allowed. Restricted to authorized accounts.
     * @dev Calls OpenZeppelin ERC20Upgradeable transfer function
     * @param to The recipient address.
     * @param value The number of tokens to transfer.
     * @return A boolean indicating whether the transfer succeeded.
     */
    function transfer(
        // TODO: maybe rework this?
        address to,
        uint256 value
    ) public override whenNotPaused nonReentrant restricted returns (bool) {
        _exchangeAllowed(_msgSender(), to);
        return super.transfer(to, value);
    }

    /**
     * @notice Transfers tokens from one address to another using an allowance. Restricted to authorized accounts.
     * @dev Calls OpenZeppelin ERC20Upgradeable transferFrom function.
     * @param from The address from which tokens are being transferred.
     * @param to The recipient address.
     * @param value The number of tokens to transfer.
     * @return A boolean indicating whether the transfer succeeded.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override whenNotPaused nonReentrant restricted returns (bool) {
        _exchangeAllowed(from, to);
        return super.transferFrom(from, to, value);
    }

    /**
     * @notice Burns a number of tokens from the sender.
     * @param value The amount of tokens to burn.
     */
    function burn(uint256 value) public whenBurnable whenNotPaused {
        if (isHolderFrozen(_msgSender())) revert UserIsFrozen();
        _burn(_msgSender(), value);
    }

    /**
     * @notice Burns tokens from a specified account. Restricted to authorized accounts.
     * @param account The address whose tokens will be burned.
     * @param value The number of tokens to burn.
     */
    function burnFrom(address account, uint256 value) public restricted {
        _burnFrom(account, value);
    }

    /**
     * @notice Defines the number of decimal places for the token.
     * RWA tokens are non-fractional and operate in whole units only.
     * @return The number of decimals (always `0`).
     */
    function decimals() public pure override returns (uint8) {
        return 0;
    }

    /**
     * @notice Verifies if a token exchange between two addresses is allowed.
     * @param from The sender address.
     * @param to The recipient address.
     */
    function _exchangeAllowed(address from, address to) internal view {
        _allowlist.exchangeAllowed(from, to);
        if (isHolderFrozen(from)) revert UserIsFrozen();
        if (isHolderFrozen(to)) revert UserIsFrozen();
    }

    /**
     * @notice Authorizes an upgrade to a new contract implementation. Restricted to authorized accounts.
     * @param newImplementation The address of the new contract implementation.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override restricted {}

    /**
     * @notice Updates internal state during token transfers, including holder management.
     * @param from The sender address.
     * @param to The recipient address.
     * @param value The number of tokens transferred.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        super._update(from, to, value);
        _updateHolders(from, to);
    }
}
