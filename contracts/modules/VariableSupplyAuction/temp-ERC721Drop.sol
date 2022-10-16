// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/*//////////////////////////////////////////////////////////////
                    TEMP ERC721Drop interface (incomplete and incorrect =)
//////////////////////////////////////////////////////////////*/

contract ERC721Drop {
    //
    struct Configuration {
        // IMetadataRenderer metadataRenderer;
        uint64 editionSize;
        uint16 royaltyBPS;
        address payable fundsRecipient;
    }

    string public name;
    string public symbol;
    address public owner;
    Configuration public config;

    // TODO use better mocking pattern for OZ AccessControlEnumerable

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    address internal minter;

    function getRoleMember(bytes32 /*role*/, uint256 /*index*/) public view returns (address) {
        return minter;
    }

    function grantRole(bytes32 /*role*/, address account) public {
        minter = account;
    }

    // TODO add few more needed IERC721 view/tx functions

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

    // TODO ask Iain for gist of actual possible approach
    function setEditionSize(uint64 _editionSize) public {

    }

    function adminMint(address to, uint256 quantity) public returns (uint256) {

    }    
}
