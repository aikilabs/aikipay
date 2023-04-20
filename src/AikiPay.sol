// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solady/utils/LibString.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import "./ERC721.sol";

/**

    Some definitions

    -lastUpdate is when last token params was adjuted
 */

contract AikiPay is ERC721 {
    using SafeTransferLib for address;

    address immutable owner;
    bool initialized;
    uint8 constant DIVISOR = 100;
    string public constant baseURI = "https://nft.aikipay.com/";
    uint256 nextTokenId;

    error NonExistentToken(uint256 _tokenID);
    error TokenNotDeposited(address _tokenAddress);
    error AlreadyInitialized();
    error NotOwnerOrWhitelisted();

    /// @notice ensure that contract is initialized only once.
    modifier notInitialized() {
        if(initialized) {
            revert AlreadyInitialized();
        }
        _;
    }

    /// @notice allows only owner or a whitelisted address
    modifier onlyOwnerOrWhiteListed() {
        if(msg.sender != owner && whitelist[msg.sender] != 2) {
            revert NotOwnerOrWhitelisted();
        }
        _;
    }

    struct Token {
        uint256 balance;
        uint256 totalPaidPerSec;
        uint8 divisor;
        uint48 lastUpdate;
    }

    struct Stream {
        uint208 amountPerSec;
        uint48 lastPaid;
        address token;
        uint48 startTime;
        uint48 endTime;
    }

    mapping(address => Token) tokens;
    mapping(uint256 => Stream) streams;

    /// @notice tracks whitelisted addresses
    /// @dev a value of `2` is whitelisted and `1`(default `0`) is not whitelisted.
    mapping(address => uint256) payerWhitelist;

    event Deposit(address token, uint256 amount);
    event NoZeroDeposit();

    /// @notice initializes a new payer contract, meant to be called once during cloning.
    function initialize(address _owner, string memory _name, string memory _symbol) external notInitialized {
        owner = _owner;
        initialized = true;
        super.initialize(_name, _symbol);
    }

    function tokenURI(uint256 _tokenID) public view virtual override returns (string memory) {
        if(_ownerOf[_tokenID] == address(0)) revert NonExistentToken(_tokenID);
        return string(
            abi.encodePacked(
                baseURI,
                LibString.toString(block.chainid),
                "/",
                LibString.toHexString(address(this)),
                "/",
                LibString.toString(_tokenID)
            )
        );
    }

    /// @notice allows anyone to deposit token to the contract.
    /// @dev native token deposit is also supported.
    function deposit(address _token, uint256 _amount) payable external {
        // ERC20 token = ERC20(_token);
            if(tokens[_token].divisor == 0) {
                tokens[_token].divisor = DIVISOR;
            }
        tokens[_token].balance += uint256(_amount * DIVISOR);
        _token.safeTransferFrom(msg.sender, address(this), _amount);
        emit Deposit(_token, _amount);
    }

    /// @notice withdraw yet to be streamed tokens.
    /// @dev callable from only `owner` or a `whitelist` address.
    function withdrawPayer(address _token, uint256 _amount) external onlyOwnerOrWhiteListed{
        Token storage token = _updateToken(_token);
        uint256 amountToWithdraw = _amount * DIVISOR;
        token.balance -= amountToWithdraw;
        _token.safeTransfer(msg.sender, _amount);
        /// emit an event
    }

    /// @notice withdraw all yet to be streamed tokens.
    /// @dev callable from only `owner` or a `whitelist` address.
    function withdrawPayerAll(address _token) external onlyOwnerOrWhiteListed{
        Token storage token = _updateToken(_token);
        uint256 amountToWithdraw = token.balance / DIVISOR;
        token.balance = 0;
        _token.safeTransfer(msg.sender, amountToWithdraw);
        /// emit an event
    }

    /// @notice adds an address to a payer's whitelist
    function addPayerWhiteList(address _addressToAdd) external onlyOwner {
        if(_addressToAdd == address(0)) revert INVALID_ADDRESS();
        if(payerWhitelist[_addressToAdd] == 2) revert ALREADY_WHITELISTED();
        payerWhitelist[_addressToAdd] = 2;
        /// emit an event
    }


    /// @notice removes an address to a payer's whitelist
    function removePayerWhiteList(address _addressToRemove) external onlyOwner {
        if(_addressToRemove == address(0)) revert INVALID_ADDRESS();
        if(payerWhitelist[_addressToRemove] != 2) revert NOT_WHITELISTED();
        payerWhitelist[_addressToRemove] = 1;
        /// emit an event
    }


    function withdraw(uint256 _id, uint256 _amount) external {
        address streamRecipient = ownerOf(_id);
        if(streamRecipient == address(0)) revert NonExistentToken();
        Stream storage stream = _updateStream(_id);
        redeemables[_id] -= amount * DIVISOR;
        stream.token.safeTransfer(streamRecipient, _amount);
        /// emit an event
    }


    function createStream(address _token, address _to, uint208 _amountPerSec, uint48 _startTime, uint48 _endTime) {
        if(_token == address(0)) revert INVALID_TOKEN();
        if(_to == address(0)) revert INVALID_ADDRESS();
        if(_amountPerSec == 0) revert INVALID_AMOUNT_PER_SEC();
        if(_startTime >= _endTime) revert INVALID_STREAM();
        _createStream(_token, _to, _amountPerSec, _startTime, _endTime);
        /// emit an event
    }


    function _createStream(address _token, address _to, uint208 _amountPerSec, uint48 _startTime, uint48 _endTime) onlyOwnerOrWhiteListed returns(uint256 id) {
        Token storage token = _updateToken(_token);
        if(block.timestamp > token.lastUpdate) revert PAYER_IN_DEBT();

        id = nextTokenId;

        uint256 owed;
        uint256 lastPaid;
        if(block.timestamp > _endTime) {
            owed = (block.timestamp - _startTime) * _amountPerSec;
        }else if(block.timestamp > _startTime) {
            owed = (block.timestamp - _startTime) * _amountPerSec;
            token.totalPaidPerSec += _amountPerSec;
            lastPaid = block.timestamp;
        }else if(_startTime > block.timestamp) {
            token.totalPaidPerSec += _amountPerSec;
            lastPaid = block.timestamp;
        }

        unchecked {
            if(token.balance >= owed) {
                token.balance -= owed;
                redeemables[id] = owed;
            }else {
                uint256 balance = token.balance;
                token.balance = 0;
                redeemables[id] = balance;
                debt[id] = owed - balance;
            }
            ++nextTokenId;
        }
        
        streams[id] = Stream(_amountPerSec, uint48(lastPaid) , _token, _startTime, _endTime);
        _safeMint(_to, id);
    }

    function _updateToken(address _token) internal returns(Token storage token) {
        token = tokens[_token];
        if(token.divisor == 0) revert TokenNotDeposited(_token);
            
        uint256 amountToStream = (block.timestamp - token.lastUpdate) * token.totalPaidPerSec;
        if(token.balance >= amountToStream) {
            token.balance -= amountToStream;
            token.lastUpdate = uint48(block.timestamp);
        }else {
            token.balance = token.balance % token.totalPaidPerSec;
            token.lastUpdate += uint48(token.balance / token.totalPaidPerSec);
        }

        /// emit an event

    }

    function _updateStream(uint256 _id) internal returns(Stream storage stream) {
        if(ownerOf(_id) == address(0)) revert NON_EXISTENT_STREAM();
        stream = streams[id];
        _updateToken(stream.token);
        unchecked {
            uint256 lastUpdate = tokens[stream.token].lastUpdate;
            uint256 amountPerSec = stream.amountPerSec;
            uint256 lastPaid = stream.lastPaid;
            uint256 startTime = stream.startTime;
            uint256 endTime = stream.endTime;

            if(startTime > lastPaid && lastUpdate >= endTime) {
                tokens[stream.token].balance -= ((lastPaid-startTime)+(lastUpdate-endTime)) * amountPerSec;
                redeemables[id] = (endTime - startTime) * amountPerSec;
                stream.lastPaid = 0;
                tokens[stream.token].totalPaidPerSec -= amountPerSec;
            }else if(lastUpdate >= startTime && startTime > lastPaid) {
                tokens[stream.token].balance += (lastPaid - startTime) * amountPerSec;
                redeemables[id] = (lastUpdate - startTime) * amountPerSec;
                streams.lastPaid = uint48(lastUpdate);
            }else if(lastUpdate >= endTime) {
                tokens[stream.token].balance += (endTime - lastUpdate) * amountPerSec;
                redeemables[id] = (endTime - lastPaid) * amountPerSec;
                stream.lastPaid = 0;
                tokens[stream.token].totalPaidPerSec -= amountPerSec;
            }else if(startTime > lastUpdate) {
                tokens[stream.token].balance += (lastUpdate-lastPaid) * amountPerSec;
                stream.lastPaid = lastUpdate;
            }else if(lastPaid >= startTime && endTime > lastUpdate) {
                redeemables[id] += (lastUpdate - lastPaid) * amountPerSec;
                streams[id].lastPaid = lastUpdate;
            }
        }

        /// emit an event.
    }



    receive() external {
        // 
    }


}
