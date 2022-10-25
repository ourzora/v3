// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/*//////////////////////////////////////////////////////////////
                    Temp Mock ERC721Drop interface
//////////////////////////////////////////////////////////////*/

// TODO consider other approaches that keep VSA module ignorant of ERC-721 Drop
// implementation specifics, including wrapping in a ERC721DropHelper or similar,
// which could extend BaseTransferHelper

// TODO improve mocking pattern for OZ AccessControlEnumerable

// TODO get the function for setting edition sizes post-initialization from Iain

contract ERC721Drop {
    //

    /*//////////////////////////////////////////////////////////////
                        OZ ERC-721
    //////////////////////////////////////////////////////////////*/

    string public name;
    string public symbol;
    mapping(address => uint256) public balanceOf;

    /*//////////////////////////////////////////////////////////////
                        OZ Ownable
    //////////////////////////////////////////////////////////////*/
    
    address public owner;

    /*//////////////////////////////////////////////////////////////
                        OZ Access Control
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    address internal minter;

    function getRoleMember(bytes32 /*role*/, uint256 /*index*/) public view returns (address) {
        return minter;
    }

    function grantRole(bytes32 /*role*/, address account) public {
        minter = account;
    }    

    /*//////////////////////////////////////////////////////////////
                        Zora ERC721Drop
    //////////////////////////////////////////////////////////////*/

    struct Configuration {
        // IMetadataRenderer metadataRenderer;
        uint64 editionSize;
        uint16 royaltyBPS;
        address payable fundsRecipient;
    }

    Configuration public config;

    function initialize(
        string memory _contractName,
        string memory _contractSymbol,
        address _initialOwner,
        address payable _fundsRecipient,
        uint64 _editionSize,
        uint16 _royaltyBPS
        // SalesConfiguration memory _salesConfig,
        // IMetadataRenderer _metadataRenderer,
        // bytes memory _metadataRendererInit
    ) public {
        name = _contractName;
        symbol = _contractSymbol;
        owner = _initialOwner;
        config = Configuration({
            editionSize: _editionSize,
            royaltyBPS: _royaltyBPS,
            fundsRecipient: _fundsRecipient
        });
    }

    function adminMint(address to, uint256 quantity) public returns (uint256) {
        balanceOf[to] += quantity;
        return 0;
    }

    function adminMintAirdrop(address[] calldata recipients) public returns (uint256) {
        for (uint256 i = 0; i < recipients.length; i++) {
            adminMint(recipients[i], 1);
        }
        return 0;
    }

    function setEditionSize(uint64 _editionSize) public {
        //
    }
}
