// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface ICarbonCreditToken {
    /**
     * @dev Emitted when the protocol treasury address is changed.
     */
    event ProtocolTreasuryChanged(address indexed newTreasury);

    /**
     * @dev Returns the address of the protocol treasury.
     */
    function protocolTreasury() external view returns (address);

    /**
     * @dev Mints a specified amount of tokens directly to the protocol treasury.
     * MUST only be callable by the MINTER_ROLE.
     * @param amount The amount of tokens to mint.
     */
    function mintToTreasury(uint256 amount) external;
} 