// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract Airdrop is
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    struct AirdropScheme {
        string name;
        address tokenCurrency;
        uint256 totalSupply;
        bytes32 whitelistMerkleRoot;
        bool isActive;
    }

    CountersUpgradeable.Counter public schemeCount;
    address public emergencyWallet;

    mapping(uint256 => AirdropScheme) private _airdropSchemes;
    mapping(uint256 => mapping(address => bool)) private _isClaimedAt;
    mapping(address => bool) private _admins;
    mapping(address => bool) private _whitelistCurrency;

    function initialize(address emergencyWallet_, address ownerAddress_)
        public
        initializer
    {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        emergencyWallet = emergencyWallet_;
        OwnableUpgradeable.transferOwnership(ownerAddress_);
    }

    event NewAirdropScheme(
        address msgSender,
        uint256 beId,
        uint256 schemeId,
        AirdropScheme scheme,
        bool isDeposit
    );
    event ActiveScheme(uint256 schemeId, bool isActive);
    event Claim(
        uint256 schemeId,
        address wallet,
        uint256 claimAmount,
        uint256 totalClaimableRemaining
    );
    event EmergencyWallet(address emergencyWallet);
    event EmergencyWithdraw(
        address emergencyWallet,
        address tokenCurrency,
        uint256 amount
    );
    event Withdraw(
        uint256 schemeId,
        address recipient,
        address tokenCurrency,
        uint256 withdrawAmount
    );
    event Admin(address admin, bool isAdmin);
    event WhitelistCurrency(address tokenCurrency, bool isWhitelist);

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    modifier schemeExist(uint256 schemeId) {
        _schemeExist(schemeId);
        _;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * contract setup functions
     */
    function setEmergencyWallet(address newEmergencyWallet) external onlyOwner {
        require(
            newEmergencyWallet != address(0),
            "New emergency address is invalid"
        );
        emergencyWallet = newEmergencyWallet;
        emit EmergencyWallet(emergencyWallet);
    }

    function setAdmin(address admin, bool isAdmin_) public onlyOwner {
        _admins[admin] = isAdmin_;
        emit Admin(admin, isAdmin_);
    }

    function setWhitelistCurrency(address tokenCurrency, bool isWhitelist)
        external
        onlyOwner
    {
        require(
            tokenCurrency.isContract() || tokenCurrency == address(0),
            "Token currency is invalid"
        );
        _whitelistCurrency[tokenCurrency] = isWhitelist;
        emit WhitelistCurrency(tokenCurrency, isWhitelist);
    }

    function emergencyWithdraw(address tokenCurrency)
        external
        whenPaused
        onlyOwner
    {
        require(
            emergencyWallet != address(0),
            "Emergency wallet have not set yet"
        );
        require(
            _isWhitelistCurrency(tokenCurrency),
            "Token currency is not whitelist"
        );
        uint256 balanceOfThis = IERC20Upgradeable(tokenCurrency).balanceOf(
            address(this)
        );
        if (balanceOfThis > 0) {
            IERC20Upgradeable(tokenCurrency).safeTransfer(
                emergencyWallet,
                balanceOfThis
            );
        }
        emit EmergencyWithdraw(emergencyWallet, tokenCurrency, balanceOfThis);
    }

    function createAirdropScheme(
        uint256 beId,
        string memory name,
        address tokenCurrency,
        uint256 totalSupply,
        bytes32 whitelistMerkleRoot,
        bool isDeposit
    ) external onlyAdmin {
        _checkAirdropSchemeInfo(
            name,
            tokenCurrency,
            totalSupply,
            whitelistMerkleRoot
        );

        schemeCount.increment();
        uint256 schemeId = schemeCount.current();
        AirdropScheme storage scheme = _airdropSchemes[schemeId];
        scheme.name = name;
        scheme.tokenCurrency = tokenCurrency;
        scheme.totalSupply = totalSupply;
        scheme.whitelistMerkleRoot = whitelistMerkleRoot;
        scheme.isActive = true;

        if (isDeposit) {
            IERC20Upgradeable(tokenCurrency).safeTransferFrom(
                _msgSender(),
                address(this),
                totalSupply
            );
        }

        emit NewAirdropScheme(_msgSender(), beId, schemeId, scheme, isDeposit);
    }

    function toggleSchemeActivation(uint256 schemeId, bool isActive)
        external
        onlyAdmin
        schemeExist(schemeId)
    {
        if (isActive) {
            require(
                _airdropSchemes[schemeId].totalSupply > 0,
                "Can not reactive this scheme"
            );
        }
        _airdropSchemes[schemeId].isActive = isActive;
        emit ActiveScheme(schemeId, isActive);
    }

    function claimAirdrop(
        uint256 schemeId,
        uint256 claimAmount,
        bytes32[] memory merkleProof
    ) external whenNotPaused nonReentrant schemeExist(schemeId) {
        require(
            schemeId >= 1 && schemeId <= schemeCount.current(),
            "Airdrop: Scheme is not exist"
        );
        require(!_isClaimedAt[schemeId][_msgSender()], "Airdrop: Claimed");

        AirdropScheme storage scheme = _airdropSchemes[schemeId];
        require(scheme.isActive, "Scheme is not active");
        bytes32 hash = keccak256(abi.encodePacked(_msgSender(), claimAmount));
        require(
            _verify(merkleProof, scheme.whitelistMerkleRoot, hash),
            "Airdrop: Sender is not whitelist"
        );

        require(scheme.isActive, "Scheme is not active");
        require(
            scheme.totalSupply > 0,
            "Airdrop: Claimable is no longer available"
        );

        scheme.totalSupply -= claimAmount;
        _isClaimedAt[schemeId][_msgSender()] = true;
        IERC20Upgradeable(scheme.tokenCurrency).safeTransfer(
            _msgSender(),
            claimAmount
        );

        emit Claim(schemeId, _msgSender(), claimAmount, scheme.totalSupply);
    }

    function withdrawAtScheme(uint256 schemeId)
        external
        onlyAdmin
        schemeExist(schemeId)
    {
        AirdropScheme storage scheme = _airdropSchemes[schemeId];
        require(!scheme.isActive, "Require scheme is deactivate");

        uint256 withdrawAmount = scheme.totalSupply;
        address tokenCurrency = scheme.tokenCurrency;

        delete _airdropSchemes[schemeId];

        IERC20Upgradeable(tokenCurrency).safeTransfer(
            _msgSender(),
            withdrawAmount
        );

        emit Withdraw(schemeId, _msgSender(), tokenCurrency, withdrawAmount);
    }

    function airdropSchemeInformation(uint256 schemeId)
        external
        view
        returns (AirdropScheme memory)
    {
        return _airdropSchemes[schemeId];
    }

    function isClaimedAtScheme(uint256 schemeId, address wallet)
        external
        view
        returns (bool)
    {
        return _isClaimedAt[schemeId][wallet];
    }

    function isAdmin(address admin) external view returns (bool) {
        return _admins[admin];
    }

    function isWhitelistCurrency(address tokenCurrency)
        external
        view
        returns (bool)
    {
        return _isWhitelistCurrency(tokenCurrency);
    }

    function _isWhitelistCurrency(address _tokenCurrency)
        internal
        view
        returns (bool)
    {
        return _whitelistCurrency[_tokenCurrency];
    }

    function _onlyAdmin() private view {
        require(_admins[_msgSender()], "Airdrop: Sender is not admin");
    }

    function _schemeExist(uint256 schemeId) private view {
        require(
            schemeId >= 1 && schemeId <= schemeCount.current(),
            "Scheme is not exist"
        );
    }

    function _checkAirdropSchemeInfo(
        string memory _name,
        address _tokenCurrency,
        uint256 _totalSupply,
        bytes32 _whitelistMerkleRoot
    ) private view {
        require(bytes(_name).length > 0, "Name must not be empty");
        require(
            _isWhitelistCurrency(_tokenCurrency),
            "Token currency is not whitelist"
        );
        require(_totalSupply > 0, "Total supply must be greater than zero");
        require(_whitelistMerkleRoot != 0x0, "Whitelist must not be empty");
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
                computedHash = keccak256(
                    abi.encodePacked(computedHash, proofElement)
                );
            } else {
                // Hash(current element of the proof + current computed hash)
                computedHash = keccak256(
                    abi.encodePacked(proofElement, computedHash)
                );
            }
        }

        // Check if the computed hash (root) is equal to the provided root
        return computedHash == _root;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
