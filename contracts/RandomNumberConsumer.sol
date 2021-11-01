pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RandomNumberConsumer is VRFConsumerBase, Ownable {

    bytes32 internal keyHash;
    uint256 internal fee;

    mapping(bytes32 => uint256) public randomResult;
    mapping(address => bool) public approvedRandomnessRequesters;

    /**
     * Constructor inherits VRFConsumerBase
     *
     * Network: Kovan
     * Chainlink VRF Coordinator address: 0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9
     * LINK token address:                0xa36085F69e2889c224210F603D836748e7dC0088
     * Key Hash: 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4
     */
    constructor(
        address _vrfCoordinator,
        address _link,
        bytes32 _keyHash,
        uint _fee
    )
        VRFConsumerBase(
            _vrfCoordinator, // VRF Coordinator
            _link  // LINK Token
        ) public
    {
        keyHash = _keyHash;
        fee = _fee;
    }

    /**
     * Requests randomness
     */
    function getRandomNumber() public returns (bytes32 requestId) {
        require(approvedRandomnessRequesters[msg.sender], "RandomNumberConsumer::getRandomNumber: msg.sender is not an approved requester of randomness");
        require(LINK.balanceOf(address(this)) >= fee, "RandomNumberConsumer::getRandomNumber: Not enough LINK");
        return requestRandomness(keyHash, fee);
    }

    function setRandomnessRequesterApproval(address _requester, bool _approvalStatus) public onlyOwner {
        approvedRandomnessRequesters[_requester] = _approvalStatus;
    }

    /**
     * Reads fulfilled randomness for a given request ID
     */
    function readFulfilledRandomness(bytes32 requestId) public view returns (uint256) {
        return randomResult[requestId];
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        randomResult[requestId] = randomness;
    }

    // function withdrawLink() external {} - Implement a withdraw function to avoid locking your LINK in the contract
}
