// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.7;

interface IOffsetVariantVRF721NFTClonable {
  function initialize(
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
  ) external;

  function mint(address recipient, uint256 quantity) external payable;
  function tokenURI(uint256 tokenId) external view returns (string memory);
  function initiateRandomDistribution() external;
  function commitRandomDistribution() external;
}