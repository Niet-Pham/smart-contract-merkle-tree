/* SPDX-License-Identifier: MIT */
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../utils/ArrayLib.sol";
import "../erc721/Box.sol";

contract GachaContract is
  UUPSUpgradeable,
  OwnableUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable
{
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using AddressUpgradeable for address;
  using CountersUpgradeable for CountersUpgradeable.Counter;

  struct GachaEvent {
    string name;
    uint256 totalBoxes;
    uint256 totalBoxesPurchased;
    bytes32 merkleRoot;
  }

  CountersUpgradeable.Counter public gachaEventCount;
  BoxContract public boxContract;

  mapping(address => bool) private _admins;
  mapping(address => bool) private _operators;
  mapping(uint256 => GachaEvent) private _gachaEvents;
  mapping(uint256 => mapping(bytes32 => bool)) private _boxDataIsUsedAtEvent;

  function initialize(address boxContract_, address ownerAddress_)
    external
    initializer
  {
    __UUPSUpgradeable_init();
    __Ownable_init();
    __Pausable_init();
    __ReentrancyGuard_init();
    OwnableUpgradeable.transferOwnership(ownerAddress_);

    boxContract = BoxContract(boxContract_);
  }

  //event
  event Admin(address admin, bool isAdmin);
  event Operator(address operator, bool isOperator);
  event Box(address boxContract);
  event NewGachaEvent(uint256 eventId, string name, uint256 totalBoxes, bytes32 merkleRoot);
  event UpdateMerkleRoot(uint256 eventId, bytes32 merkleRoot);
  event BuyBox(uint256 eventId, address buyer, uint256 boxId, bytes32 boxData);

  modifier onlyOperator() {
    require(_operators[_msgSender()], "Gacha: Sender is not operator");
    _;
  }

  modifier onlyAdmin() {
    require(_admins[_msgSender()], "Gacha: Sender is not admin");
    _;
  }

  modifier gachaEventExist(uint256 eventId) {
    require(
      eventId > 0 && eventId <= gachaEventCount.current(),
      "Event is not exist"
    );
    _;
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  function createGachaEvent(string memory name, uint256 totalBoxes, bytes32 merkleRoot)
    external
    onlyOperator
  {
    require(bytes(name).length > 0, "Name must not be empty");
    require(totalBoxes > 0, "Total boxes must be than greater than zero");
    require(merkleRoot > 0, "merkleRoot");

    gachaEventCount.increment();
    uint256 id = gachaEventCount.current();
    GachaEvent storage newGachaEvent = _gachaEvents[id];
    newGachaEvent.name = name;
    newGachaEvent.totalBoxes = totalBoxes;
    newGachaEvent.merkleRoot = merkleRoot;

    emit NewGachaEvent(id, name, totalBoxes, merkleRoot);
  }

  function updateMerkleRoot(uint256 eventId, bytes32 merkleRoot)
    external
    whenNotPaused
    onlyOperator
    gachaEventExist(eventId)
  {
    require(merkleRoot != 0x0, "Merkle root must not empty");

    GachaEvent storage gachaEvent = _gachaEvents[eventId];
    gachaEvent.merkleRoot = merkleRoot;

    emit UpdateMerkleRoot(eventId, merkleRoot);
  }

  function buyBox(
    uint256 eventId,
    bytes32 boxData,
    bytes32[] memory merkleProof
  ) external payable whenNotPaused gachaEventExist(eventId) nonReentrant {
    GachaEvent storage gachaEvent = _gachaEvents[eventId];

    require(gachaEvent.merkleRoot != 0x0, "Merkle root is empty");
    // bytes32 hash = keccak256(abi.encodePacked(boxData));
    require(
      _verify(merkleProof, gachaEvent.merkleRoot, boxData),
      "Data is invalid"
    );

    require(!_boxDataIsUsedAtEvent[eventId][boxData], "Box data is used");

    require(
      gachaEvent.totalBoxesPurchased < gachaEvent.totalBoxes,
      "Out of stock"
    );

    uint256 boxId = boxContract.mint(_msgSender(), boxData);

    //decrease amount box in event
    gachaEvent.totalBoxesPurchased++;
    _boxDataIsUsedAtEvent[eventId][boxData] = true;

    emit BuyBox(eventId, _msgSender(), boxId, boxData);
  }

  function setBoxContract(address newBoxContract) external onlyOwner {
    require(
      newBoxContract.isContract() && newBoxContract != address(0),
      "New box contract is invalid"
    );
    boxContract = BoxContract(newBoxContract);
    emit Box(newBoxContract);
  }

  function setOperator(address operator, bool isOperator_) public onlyOwner {
    _operators[operator] = isOperator_;
    emit Operator(operator, isOperator_);
  }

  function setAdmin(address admin, bool isAdmin_) external onlyOwner {
    _admins[admin] = isAdmin_;
    emit Admin(admin, isAdmin_);
  }

  function gachaEventInformation(uint256 eventId)
    external
    view
    returns (
      string memory name,
      uint256 totalBoxes,
      bytes32 merkleRoot
    )
  {
    GachaEvent storage gacha = _gachaEvents[eventId];
    name = gacha.name;
    totalBoxes = gacha.totalBoxes;
    merkleRoot = gacha.merkleRoot;
  }

  function isOperator(address operator) external view returns (bool) {
    return _operators[operator];
  }

  function isAdmin(address admin) external view returns (bool) {
    return _admins[admin];
  }

  function _verify(
    bytes32[] memory _proof,
    bytes32 _root,
    bytes32 _leaf
  ) internal pure returns (bool) {
    bytes32 computedHash = _leaf;

    for (uint256 i = 0; i < _proof.length; i++) {
      bytes32 proofElement = _proof[i];

      if (computedHash <= proofElement) {
        // Hash(current computed hash + current element of the proof)
        computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
      } else {
        // Hash(current element of the proof + current computed hash)
        computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
      }
    }

    // Check if the computed hash (root) is equal to the provided root
    return computedHash == _root;
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}
}
