// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NPMarketplace is Ownable(msg.sender), ReentrancyGuard, IERC721Receiver {
    // Listing structure to store NFT sale details
    struct Listing {
        address nftContract;
        uint256 tokenId;
        address seller;
        uint256 price;
        bool isActive;
    }

    // Events for marketplace actions
    event NFTListed(
        address indexed nftContract, 
        uint256 indexed tokenId, 
        address indexed seller, 
        uint256 price
    );
    event NFTPurchased(
        address indexed nftContract, 
        uint256 indexed tokenId, 
        address indexed buyer, 
        address seller, 
        uint256 price
    );
    event NFTDelisted(
        address indexed nftContract, 
        uint256 indexed tokenId, 
        address indexed seller
    );

    // Marketplace fee (percentage)
    uint256 public constant MARKETPLACE_FEE_PERCENTAGE = 2;

    // Mapping to store active listings
    mapping(address => mapping(uint256 => Listing)) public listings;

    // NEOX token contract
    IERC20 public neoxToken;

    // Constructor to set NEOX token address
    constructor(address _neoxTokenAddress) {
        require(_neoxTokenAddress != address(0), "Invalid token address");
        neoxToken = IERC20(_neoxTokenAddress);
    }

    // Function to list an NFT for sale
    function listNFT(
        address _nftContract, 
        uint256 _tokenId, 
        uint256 _price
    ) external {
        require(_price > 0, "Price must be greater than zero");
        
        IERC721 nftContract = IERC721(_nftContract);
        require(
            nftContract.ownerOf(_tokenId) == msg.sender, 
            "Must own the NFT"
        );
        require(
            nftContract.getApproved(_tokenId) == address(this) || 
            nftContract.isApprovedForAll(msg.sender, address(this)), 
            "Contract must be approved to transfer NFT"
        );

        // Transfer NFT to marketplace contract for custody
        nftContract.safeTransferFrom(msg.sender, address(this), _tokenId);

        // Create listing
        listings[_nftContract][_tokenId] = Listing({
            nftContract: _nftContract,
            tokenId: _tokenId,
            seller: msg.sender,
            price: _price,
            isActive: true
        });

        emit NFTListed(_nftContract, _tokenId, msg.sender, _price);
    }

    // Function to purchase an NFT
    function purchaseNFT(
        address _nftContract, 
        uint256 _tokenId
    ) external nonReentrant {
        Listing memory listing = listings[_nftContract][_tokenId];
        
        require(listing.isActive, "NFT not listed for sale");
        
        // Check NEOX token balance and allowance
        require(
            neoxToken.balanceOf(msg.sender) >= listing.price, 
            "Insufficient NEOX balance"
        );
        require(
            neoxToken.allowance(msg.sender, address(this)) >= listing.price, 
            "Insufficient NEOX token allowance"
        );

        // Calculate marketplace fee
        uint256 marketplaceFee = (listing.price * MARKETPLACE_FEE_PERCENTAGE) / 100;
        uint256 sellerProceeds = listing.price - marketplaceFee;

        // Transfer tokens to seller
        require(
            neoxToken.transferFrom(msg.sender, listing.seller, sellerProceeds),
            "Token transfer to seller failed"
        );

        // Transfer marketplace fee to contract owner
        require(
            neoxToken.transferFrom(msg.sender, owner(), marketplaceFee),
            "Token transfer of marketplace fee failed"
        );

        // Transfer NFT directly from marketplace to buyer
        IERC721(_nftContract).safeTransferFrom(
            address(this), 
            msg.sender, 
            _tokenId
        );

        // Remove listing
        delete listings[_nftContract][_tokenId];

        emit NFTPurchased(
            _nftContract, 
            _tokenId, 
            msg.sender, 
            listing.seller, 
            listing.price
        );
    }

    // Function to delist an NFT
    function delistNFT(
        address _nftContract, 
        uint256 _tokenId
    ) external {
        Listing storage listing = listings[_nftContract][_tokenId];
        
        require(listing.isActive, "NFT not listed");
        require(listing.seller == msg.sender, "Only seller can delist");

        // Transfer NFT back to seller
        IERC721(_nftContract).safeTransferFrom(
            address(this),
            msg.sender,
            _tokenId
        );

        // Remove listing
        delete listings[_nftContract][_tokenId];

        emit NFTDelisted(_nftContract, _tokenId, msg.sender);
    }

    // Function to get current listing details
    function getListing(
        address _nftContract, 
        uint256 _tokenId
    ) external view returns (Listing memory) {
        return listings[_nftContract][_tokenId];
    }

    // Required implementation for IERC721Receiver
    function onERC721Received(
        address, 
        address, 
        uint256, 
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // Update NEOX token address (only owner)
    function updateNeoxToken(address _newTokenAddress) external onlyOwner {
        require(_newTokenAddress != address(0), "Invalid token address");
        neoxToken = IERC20(_newTokenAddress);
    }
}
