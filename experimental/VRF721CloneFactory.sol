// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./interfaces/IVRF721Clonable.sol";

contract OffsetVariantVRF721NFTCloneFactory {

    event VRF721CloneDeployed(address indexed cloneAddress);

    address public referenceVRF721;
    address public cloner;

    constructor(address _referenceVRF721) public {
        referenceVRF721 = _referenceVRF721;
        cloner = msg.sender;
    }

    modifier onlyCloner {
        require(msg.sender == cloner);
        _;
    }

    function changeCloner(address _newCloner) external onlyCloner {
        cloner = _newCloner;
    }

    function newVRF721Clone(
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
    ) external onlyCloner returns (address) {
        // Create new VRF721Clone
        address newVRF721CloneAddress = Clones.clone(referenceVRF721);
        IOffsetVariantVRF721NFTClonable vrf721 = IOffsetVariantVRF721NFTClonable(newVRF721CloneAddress);
        vrf721.initialize(
            _tokenName,
            _tokenSymbol,
            _preRevealURI,
            _baseURI,
            _suffixBaseURI,
            _supplyLimit,
            _mintingStartTimeUnix,
            _mintingEndTimeUnix,
            _mintingPriceWei,
            _singleOrderLimit,
            _vrfProvider
        );
        emit VRF721CloneDeployed(newVRF721CloneAddress);
        return newVRF721CloneAddress;
    }

}