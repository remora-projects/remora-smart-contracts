// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @dev Interface of ERC-20 contract
 */
interface IERC20 {
    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Returns the number of decimals used by the ERC20 token
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Moves 'value' amount of tokens from sender to 'to'
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Moves 'value' amount of tokens from 'from' to 'to' using allowance.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}
