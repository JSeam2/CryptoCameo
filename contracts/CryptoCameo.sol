//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CryptoCameo is ReentrancyGuard {
    struct Cameo {
        address seller;
        int256 reputation; // can be positive or negative
        uint256 price; // in wei
        uint256 deliveryTime; // time diff in unix time
        string profileUri; // profile details for seller
        uint16 openSlots; // number of open slots, this will decrease till 0 
    }

    struct Agreement {
        address seller;
        address buyer;
        uint256 price; // repeat price here because the price can change if cameo struct is edited
        uint256 deadline; // deadline set by buyer in unix time, otherwise buyer can withdraw. This is equal or greater than delivery time stated by seller
        string requestUri; // request uri for buyer to describe task
        string submissionUri; // submission uri for seller to submit task, if not null seller can withdraw
        bool withdrawn;
        bool refunded;
        bool review; // bool flag to allow a buyer to increment or decrement reputation on a seller
    }

    mapping(address => Cameo) public _cameo;
    mapping(uint256 => Agreement) public _agreement;
    uint256 public _agreementCount;

    event SetCameo (
        address indexed seller,
        uint256 price,
        uint256 deliveryTime,
        string profileUri
    );

    event SetOpenSlots (
        address indexed seller,
        uint256 openSlots
    );

    event NewAgreement (
        uint256 id,
        address indexed seller,
        address indexed buyer,
        uint256 price,
        uint256 deadline,
        string requestUri
    );

    event Refund (uint256 id);
    event Withdraw (uint256 id);
    event Review (
        uint256 id, 
        address indexed seller,
        address indexed buyer,
        bool goodReview
    );

    // use this for initialization and modification of cameo
    function setCameo(
        uint256 price, 
        uint256 deliveryTime, 
        string memory profileUri
    ) 
        external 
    {
        _cameo[msg.sender].seller = msg.sender;  
        // _cameo[msg.sender].reputation = 0; this will be zero by default
        _cameo[msg.sender].price = price;
        _cameo[msg.sender].deliveryTime = deliveryTime;
        _cameo[msg.sender].profileUri = profileUri;
        // _cameo[msg.sender].openSlots = 0; this will be zero by default
        
        emit SetCameo(msg.sender, price, deliveryTime, profileUri);
    }

    // sets all the possible number of open slots
    // to put a reasonable number otherwise a seller can fail to deliver
    // this would reduce reputation
    function setOpenSlots(uint16 openSlots) external {
        _cameo[msg.sender].openSlots = openSlots;

        emit SetOpenSlots(msg.sender, openSlots);
    }

    function buy(
        address seller, 
        uint256 deadline, 
        string memory requestUri
    ) 
        external 
        payable
        returns (uint256) 
    {
        require(msg.sender != seller, "Buyer cannot be seller");
        require(deadline > block.timestamp + _cameo[seller].deliveryTime, "Please set a reasonable deadline");
        require(msg.value >= _cameo[seller].price, "Not enough funds");
        require(_cameo[seller].openSlots > 0, "No more open slots");

        _agreementCount++;
        _agreement[_agreementCount].seller = seller;
        _agreement[_agreementCount].buyer = msg.sender;
        _agreement[_agreementCount].price = _cameo[seller].price;
        _agreement[_agreementCount].deadline = deadline;
        _agreement[_agreementCount].requestUri = requestUri;

        // decrement openslots
        _cameo[seller].openSlots--;

        emit NewAgreement (
            _agreementCount,
            seller,
            msg.sender,
            _cameo[seller].price,
            deadline,
            requestUri
        );
        emit SetOpenSlots (
            seller,
            _cameo[seller].openSlots
        );
        
        return _agreementCount;
    }

    // if task isn't delivered within deadline reputation score will decrease
    function refund(uint256 agreementId) external nonReentrant {
        // prevent accidental triggers by seller
        require(msg.sender == _agreement[agreementId].buyer, "Not buyer");
        require(block.timestamp > _agreement[agreementId].deadline, "Deadline has not passed");
        require(bytes(_agreement[agreementId].submissionUri).length > 0, "Submission has been provided");
        require(_agreement[agreementId].withdrawn == false, "Already withdrawn funds");
        require(_agreement[agreementId].refunded == false, "Already refunded funds");

        _agreement[agreementId].refunded = true;
        _agreement[agreementId].review = true;
        _cameo[_agreement[agreementId].seller].reputation--;

        (bool sent,) = msg.sender.call{value: _agreement[agreementId].price}("");
        require(sent, "Refund failed");

        emit Refund(agreementId);
    }

    function withdraw(uint256 agreementId, string memory submissionUri) external nonReentrant {
        // prevent accidental triggers by buyer
        require(msg.sender == _agreement[agreementId].seller, "Not seller");
        require(block.timestamp <= _agreement[agreementId].deadline, "Deadline has passed");
        require(_agreement[agreementId].withdrawn == false, "Already withdrawn funds");
        require(_agreement[agreementId].refunded == false, "Already refunded funds");

        _agreement[agreementId].withdrawn = true;
        _agreement[agreementId].submissionUri = submissionUri;

        (bool sent,) = msg.sender.call{value: _agreement[agreementId].price}("");
        require(sent, "Withdraw failed");

        emit Withdraw(agreementId);
    }

    function review(uint256 agreementId, bool goodReview) external {
        // prevent accidental triggers by seller
        require(msg.sender == _agreement[agreementId].buyer, "Not buyer");
        require(_agreement[agreementId].review == false, "Already reviewed");

        _agreement[agreementId].review = true;

        if (goodReview) {
            _cameo[_agreement[agreementId].seller].reputation++;
        } else {
            _cameo[_agreement[agreementId].seller].reputation--;
        }

        emit Review (
            agreementId, 
            _agreement[agreementId].seller,
            _agreement[agreementId].buyer,
            goodReview
        );
    }
}
