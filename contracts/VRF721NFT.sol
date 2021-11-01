// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.7;

// OpenZeppelin Contracts @ version 4.3.2
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IRandomNumberConsumer.sol";

/**
 * @title VRF721NFT
 * @notice ERC-721 NFT Contract with VRF-powered offset after minting period completion
 *
 * Key features:
 * - Uses Chainlink VRF to establish random distribution at time of "reveal"
 */
contract VRF721NFT is ERC721, Ownable {

  // Controlled variables
  using Counters for Counters.Counter;
  Counters.Counter private _tokenIds;
  bool public isRandomnessRequested;
  bytes32 public randomNumberRequestId;
  uint256 public randomOffset;

  // Configurable variables
  string public preRevealURI;
  string public baseURI;
  string public suffixBaseURI;
  uint256 public supplyLimit;
  uint256 public mintingStartTimeUnix;
  uint256 public mintingEndTimeUnix;
  uint256 public mintingPriceWei;
  uint256 public singleOrderLimit;
  address public vrfProvider;

  constructor(
    string memory _tokenName,
    string memory _tokenSymbol,
    string memory _preRevealURI,
    string memory _baseURI,
    string memory _suffixBaseURI,
    uint256 _supplyLimit,
    uint256 _mintingStartTimeUnix,
    uint256 _mintingEndTimeUnix,
    uint256 _mintingPriceWei,
    uint256 _singleOrderLimit,
    address _vrfProvider
  ) public ERC721(_tokenName, _tokenSymbol) {
    randomOffset = 0; // Must be zero at time of deployment
    preRevealURI = _preRevealURI;
    baseURI = _baseURI;
    suffixBaseURI = _suffixBaseURI; // Usually ".json"
    supplyLimit = _supplyLimit;
    mintingStartTimeUnix = _mintingStartTimeUnix;
    mintingEndTimeUnix = _mintingEndTimeUnix;
    mintingPriceWei = _mintingPriceWei;
    singleOrderLimit = _singleOrderLimit;
    vrfProvider = _vrfProvider;
  }

  function mint(address recipient, uint256 quantity) external payable returns (uint256) {
    // We increment first because we want our first token ID to have an ID of 1
    // due to our wrap around logic using the offset
    _tokenIds.increment();
    uint256 newTokenId = _tokenIds.current();

    require(block.timestamp >= mintingStartTimeUnix, "VRF721NFT::mint: minting period has not started");
    require(block.timestamp <= mintingEndTimeUnix, "VRF721NFT::mint: minting period has ended");
    require((newTokenId + quantity) <= supplyLimit, "VRF721NFT::mint: would cause total supply to exceed max supply");
    require(quantity <= singleOrderLimit, "VRF721NFT::mint: quantity exceeds max per transaction");
    require((msg.value) == (mintingPriceWei * quantity), "VRF721NFT::mint: incorrect ETH value provided");

    _mint(recipient, newTokenId);

    return newTokenId;
  }

  function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

    string memory base = _baseURI();

    // If randomOffset hasn't been revealed, return the token URI (preRevealURI).
    if (randomOffset == 0) {
      return preRevealURI;
    }

    // Uses the VRF-provided randomOffset to determine which metadata file is used for the requested tokenId
    uint256 supply = _tokenIds.current();
    uint256 offsetTokenId;
    if((tokenId + randomOffset) <= supply) {
      // e.g. with a randomOffset of 2, and a supply of 10, and a tokenId of 5: offsetTokenId = 7 (5 + 2)
      offsetTokenId = tokenId + randomOffset;
    } else {
      // e.g. with a randomOffset of 2, and a supply of 10, and a tokenId of 9: offsetTokenId = 1 (wraps around from 9 -> 1: (2 - (10 - 9)))
      offsetTokenId = (randomOffset - (supply - tokenId));
    }

    // Concatenate the tokenID along with the suffixBaseURI to the baseURI
    return string(abi.encodePacked(base, offsetTokenId, suffixBaseURI));
  }

  function initiateRandomDistribution() external {
    uint256 supply = _tokenIds.current();
    require(supply > 0, "VRF721NFT::beginReveal: supply must be more than 0");
    require(isRandomnessRequested == false, "VRF721NFT::beginReveal: request for random number has already been initiated");
    IRandomNumberConsumer randomNumberConsumer = IRandomNumberConsumer(vrfProvider);
    randomNumberRequestId = randomNumberConsumer.getRandomNumber();
    isRandomnessRequested = true;
  }

  function commitRandomDistribution() external {
    require(isRandomnessRequested == true, "VRF721NFT::completeReveal: request for random number has not been initiated");
    IRandomNumberConsumer randomNumberConsumer = IRandomNumberConsumer(vrfProvider);
    uint256 result = randomNumberConsumer.readFulfilledRandomness(randomNumberRequestId);
    require(result > 0, "VRF721NFT::completeReveal: randomResult has not been provided to vrfProvider");
    randomOffset = result % _tokenIds.current();
  }

}