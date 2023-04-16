pragma solidity ^0.8.13;

import "solady/utils/LibClone.sol";
import "./AikiPay.sol";
import "./ERC721.sol";

contract AikiPayFactory {
    using LibClone for address;
    AikiPay masterAikiPayerImpl;

    /// @notice Emitted when a new Payer contract is created.
    event PayerCreated(address payer, address owner);

    /// @notice deploys the Payer contract Implementation of the clones.
    constructor() {
        masterAikiPayerImpl = new AikiPay();
    }

    /// @notice clones and intializes an ERC721 compatible Payer contract.
    /// @todo can we set ERC20 token when initializing the payer?
    function initializePayer() external {
        address owner = msg.sender
        bytes memory data = _initData();
        address cloneAikiPayer = address(masterAikiPayerImpl).cloneDeterministic(bytes32(uint256(uint160(owner))));
        (bool success, bytes memory _d) = cloneAikiPayer.call(data);
        if(!success) revert();
        emit PayerCreated(cloneAikiPayer, owner);
    }

    function predictAddress(address _owner) external {
        bytes32 salt = bytes32(uint256(uint160(_owner)));
        address(masterAikiPayerImpl).predictDeterministic(salt, address(this));
    }

    function _initData() internal returns(bytes memory data_) {
        bytes4 initSelector = 0x90657147;
        data_ = abi.encodePacked(initSelector, abi.encode("AikiPay Stream", "AIKI-PAY-TOKEN-STREAM-V1"));
    }

}