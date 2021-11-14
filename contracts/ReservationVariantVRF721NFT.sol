// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.7;

// OpenZeppelin Contracts @ version 4.3.2
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./interfaces/IRandomNumberConsumer.sol";

/**
 * @title ReservationVariantVRF721NFT
 * @notice ERC-721 NFT Contract with VRF-powered offset after reservation period completion
 *
 * Key features:
 * - Uses Chainlink VRF to establish random distribution at time of "reveal"
 */
contract ReservationVariantVRF721NFT is ERC721, Ownable {
  using Strings for uint256;

  // Controlled state variables
  using Counters for Counters.Counter;
  Counters.Counter private _reservationIds;
  bool public isRandomnessRequested;
  bytes32 public randomNumberRequestId;
  uint256 public vrfResult;
  uint256 public randomOffset;
  mapping(address => uint256[]) public buyerToReservationIds;
  mapping(uint256 => address) public reservationIdToBuyer;
  mapping(address => uint256) public buyerToRedeemedReservationCount;

  // Configurable state variables
  string public preRevealURI;
  string public baseURI;
  string public suffixBaseURI;
  uint256 public supplyLimit;
  uint256 public reservationStartTimeUnix;
  uint256 public reservationEndTimeUnix;
  uint256 public reservationPriceWei;
  uint256 public singleOrderLimit;
  address public vrfProvider;

  // Events
  event PlacedReservation(address reserver, uint256 amount);
  event RequestedVRF(bytes32 requestId);
  event CommittedVRF(bytes32 requestId, uint256 vrfResult, uint256 randomOffset);
  event MintedOffset(address minter, uint256 reservationId, uint256 tokenId);

  constructor(
    string memory _reservationName,
    string memory _reservationSymbol,
    string memory _preRevealURI,
    string memory _baseURI,
    string memory _suffixBaseURI,
    uint256 _supplyLimit,
    uint256 _reservationStartTimeUnix,
    uint256 _reservationEndTimeUnix,
    uint256 _reservationPriceWei,
    uint256 _singleOrderLimit,
    address _vrfProvider
  ) public ERC721(_reservationName, _reservationSymbol) {
    randomOffset = 0; // Must be zero at time of deployment
    preRevealURI = _preRevealURI;
    baseURI = _baseURI;
    suffixBaseURI = _suffixBaseURI; // Usually ".json"
    supplyLimit = _supplyLimit;
    reservationStartTimeUnix = _reservationStartTimeUnix;
    reservationEndTimeUnix = _reservationEndTimeUnix;
    reservationPriceWei = _reservationPriceWei;
    singleOrderLimit = _singleOrderLimit;
    vrfProvider = _vrfProvider;
  }

  function purchaseReservation(uint256 quantity) external payable {
    require(block.timestamp >= reservationStartTimeUnix, "ReservationVariantVRF721NFT::purchaseReservation: reservation period has not started");
    require(block.timestamp <= reservationEndTimeUnix, "ReservationVariantVRF721NFT::purchaseReservation: reservation period has ended");
    require((msg.value) == (reservationPriceWei * quantity), "ReservationVariantVRF721NFT::purchaseReservation: incorrect ETH value provided");
    require(quantity <= singleOrderLimit, "ReservationVariantVRF721NFT::purchaseReservation: quantity exceeds max per transaction");
    require((_reservationIds.current() + quantity) <= supplyLimit, "ReservationVariantVRF721NFT::purchaseReservation: would cause total supply to exceed max supply");

    // We increment first because we want our first reservation ID to have an ID of 1 instead of 0
    // (makes wrapping from max -> min slightly easier)
    for(uint256 i = 0; i < quantity; i++) {
      _reservationIds.increment();
      uint256 newReservationId = _reservationIds.current();
      buyerToReservationIds[msg.sender].push(newReservationId);
      reservationIdToBuyer[newReservationId] = msg.sender;
    }

    emit PlacedReservation(msg.sender, quantity);
  }

  function addressToReservationCount(address _address) public view returns (uint256) {
    return buyerToReservationIds[_address].length;
  }

  function mint(uint256[] memory _mintReservationIds) external {
    require(vrfResult > 0, "ReservationVariantVRF721NFT::mint: vrfResult has not yet been set");
    uint256[] memory reservationIdsMemory = buyerToReservationIds[msg.sender];
    require(reservationIdsMemory.length > 0, "ReservationVariantVRF721NFT::mint: msg.sender has not purchased any reservations");
    uint256 buyerToRedeemedReservationCountMemory = buyerToRedeemedReservationCount[msg.sender];
    require(buyerToRedeemedReservationCountMemory < reservationIdsMemory.length, "ReservationVariantVRF721NFT::mint: all msg.sender reservations redeemed");
    uint256 reservationSupply = _reservationIds.current();
    for(uint256 i = 0; i < _mintReservationIds.length; i++) {
      require(reservationIdToBuyer[_mintReservationIds[i]] == msg.sender, "ReservationVariantVRF721NFT::mint: mintId not assigned to msg.sender");
      // Uses the VRF-provided randomOffset to determine which metadata file is used for the requested reservationId
      uint256 offsetTokenId;
      if((_mintReservationIds[i] + randomOffset) <= reservationSupply) {
        // e.g. with a randomOffset of 2, and a reservationSupply of 10, and a reservationId of 5: offsetTokenId = 7 (5 + 2)
        offsetTokenId = _mintReservationIds[i] + randomOffset;
      } else {
        // e.g. with a randomOffset of 2, and a reservationSupply of 10, and a reservationId of 9: offsetTokenId = 1 (wraps around from 9 -> 1: (2 - (10 - 9)))
        offsetTokenId = (randomOffset - (reservationSupply - _mintReservationIds[i]));
      }
      _mint(msg.sender, offsetTokenId);
      emit MintedOffset(msg.sender, _mintReservationIds[i], offsetTokenId);
    }
    buyerToRedeemedReservationCount[msg.sender] += _mintReservationIds.length;
  }

  function tokenURI(uint256 reservationId) public view virtual override returns (string memory) {
    require(_exists(reservationId), "ERC721Metadata: URI query for nonexistent reservation");

    // If vrfResult hasn't been revealed, return the reservation URI (preRevealURI).
    if (vrfResult == 0) {
      return preRevealURI;
    }

    // Concatenate the reservationID along with the suffixBaseURI to the baseURI
    return string(abi.encodePacked(baseURI, reservationId.toString(), suffixBaseURI));
  }

  function initiateRandomDistribution() external {
    require(block.timestamp > reservationEndTimeUnix, "ReservationVariantVRF721NFT::mint: reservation period has not ended");
    uint256 reservationSupply = _reservationIds.current();
    require(reservationSupply > 0, "ReservationVariantVRF721NFT::beginReveal: reservation supply must be more than 0");
    require(isRandomnessRequested == false, "ReservationVariantVRF721NFT::beginReveal: request for random number has already been initiated");
    IRandomNumberConsumer randomNumberConsumer = IRandomNumberConsumer(vrfProvider);
    randomNumberRequestId = randomNumberConsumer.getRandomNumber();
    isRandomnessRequested = true;
    emit RequestedVRF(randomNumberRequestId);
  }

  function commitRandomDistribution() external {
    require(isRandomnessRequested == true, "ReservationVariantVRF721NFT::completeReveal: request for random number has not been initiated");
    IRandomNumberConsumer randomNumberConsumer = IRandomNumberConsumer(vrfProvider);
    uint256 result = randomNumberConsumer.readFulfilledRandomness(randomNumberRequestId);
    require(result > 0, "ReservationVariantVRF721NFT::completeReveal: randomResult has not been provided to vrfProvider");
    vrfResult = result;
    randomOffset = result % _reservationIds.current();
    emit CommittedVRF(randomNumberRequestId, vrfResult, randomOffset);
  }

}