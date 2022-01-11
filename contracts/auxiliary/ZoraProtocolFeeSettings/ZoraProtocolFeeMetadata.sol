// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {IFeeTokenURI} from "./IFeeTokenURI.sol";
import {IPublicSharedMetadata} from "./IPublicSharedMetadata.sol";

interface IZorbRenderer {
    function zorbForAddress(address user) external returns (string memory);
}

contract ZoraProtocolFeeMetadata is IFeeTokenURI {
    IPublicSharedMetadata private immutable sharedMetadata;
    IZorbRenderer private immutable zorbRenderer;

    constructor(IPublicSharedMetadata _sharedMetadata, IZorbRenderer _zorbRenderer) {
        sharedMetadata = _sharedMetadata;
        zorbRenderer = _zorbRenderer;
    }

    function renderFee(uint16 fee, address feeRecipient) internal view returns (bytes memory) {
        uint256 feePercent = fee / 100;
        uint256 feeBpsPart = fee % 100;

        return
            abi.encodePacked(
                '<tspan x="427" y="752.977">',
                sharedMetadata.numberToString(fee),
                sharedMetadata.numberToString(feeBpsPart),
                "%",
                "</tspan>",
                '</text><text text-anchor="start"><tspan x="12" y="812">',
                sharedMetadata.numberToString(uint256(uint160(feeRecipient))),
                "</tspan></text></svg>"
            );
    }

    function renderSVG(
        address owner,
        address module,
        uint16 fee,
        address feeRecipient
    ) public returns (string memory) {
        return
            sharedMetadata.base64Encode(
                abi.encodePacked(
                    '<svg width="500" height="900" viewBox="0 0 500 900" fill="none" xmlns="http://www.w3.org/2000/svg"><defs><style>'
                    "text { font-family: CourierFont; fill: white; white-space: pre; letter-spacing: 0.05em; font-size: 14px; } text.eyebrow { fill-opacity: 0.4; }"
                    '</style></defs><rect x="38" y="683" width="422" height="44" rx="1" fill="black" /><rect x="38.5" y="683.5" width="421" height="43" rx="0.5" stroke="white" stroke-opacity="0.08" /><rect x="39" y="41" width="422" height="65" rx="1" fill="black" /> <rect x="39.5" y="41.5" width="421" height="64" rx="0.5" stroke="white" stroke-opacity="0.08" /><rect x="39" y="105" width="422" height="35" rx="1" fill="black" /><rect x="39.5" y="105.5" width="421" height="34" rx="0.5" stroke="white" stroke-opacity="0.08" /><path transform="translate(57, 57)" fill-rule="evenodd" clip-rule="evenodd" d="M2.07683 0V6.21526H28.2708L5.44618 14.2935C3.98665 14.8571 2.82212 15.6869 1.96814 16.7828C1.11416 17.8787 0.539658 19.0842 0.244645 20.3836C-0.0503676 21.6986 -0.0814215 23.0294 0.16701 24.3914C0.415442 25.7534 0.896778 26.9902 1.64207 28.1174C2.37184 29.229 3.36557 30.1526 4.5922 30.8571C5.83436 31.5616 7.29389 31.9217 8.98633 31.9217H50.8626L50.8703 31.8988C51.1535 31.914 51.4386 31.9217 51.7255 31.9217C60.4671 31.9217 67.5474 24.7828 67.5474 15.9687C67.5474 12.3143 66.333 8.94525 64.2882 6.25304L89.4471 6.2935C90.5651 6.2935 91.388 6.60661 91.9159 7.23284C92.4594 7.85906 92.7078 8.54791 92.6767 9.29937C92.6457 10.0508 92.3351 10.7397 91.7606 11.3659C91.1706 11.9921 90.3322 12.3052 89.2142 12.3052L67.7534 12.3563V12.7123L98.8254 31.9742V31.9061H105.036L104.912 9.04895C104.912 8.45404 105.036 7.93741 105.285 7.46774C105.533 7.01373 105.875 6.65365 106.309 6.43447C106.744 6.21529 107.257 6.13701 107.816 6.19964C108.375 6.26226 108.98 6.5284 109.617 6.98241L143.947 32V24.3444L113.467 2.12919C111.992 1.0333 110.377 0.391416 108.67 0.172238C106.962 -0.0469397 105.362 0.125272 103.887 0.673217C102.412 1.22116 101.186 2.12919 100.223 3.41294C99.2447 4.6967 98.7633 6.29357 98.7633 8.2192V24.7626L87.2423 18.1135L90.0682 18.0665C92.0091 18.0508 93.6084 17.5812 94.8971 16.6888C96.1858 15.7808 97.133 14.6692 97.7385 13.3385C98.3441 11.9921 98.608 10.5518 98.5459 8.98626C98.4838 7.43636 98.0801 5.98039 97.3193 4.66532C96.5585 3.35025 95.4716 2.23871 94.0431 1.36199C92.6146 0.485282 90.829 0.0469261 88.6863 0.0469261H59.4304L52.8915 0.041576C52.5116 0.0140175 52.1279 0 51.741 0C51.3629 0 50.9878 0.0133864 50.6163 0.0397145L2.07683 0ZM37.7103 8.5589L7.86839 20.227C7.23178 20.4932 6.79703 20.9315 6.56412 21.5264C6.33122 22.1213 6.28464 22.7319 6.43991 23.3425C6.59518 23.953 6.93677 24.501 7.43364 24.9706C7.9305 25.4403 8.59816 25.6751 9.42109 25.6751L39.1905 25.7073C37.1293 23.0135 35.9035 19.6361 35.9035 15.9687C35.9035 13.2949 36.5565 10.7739 37.7103 8.5589ZM61.3522 15.9687C61.3522 10.6145 57.0357 6.26223 51.741 6.26223C46.4308 6.26223 42.1143 10.6145 42.1298 15.9687C42.1298 21.3072 46.4308 25.6595 51.741 25.6595C57.0357 25.6595 61.3522 21.3229 61.3522 15.9687Z" fill="white" />'
                    '<text><tspan x="57" y="125.076">The NFT Marketplace Protocol</tspan></text><rect x="38" y="726" width="422" height="44" rx="1" fill="black" /><rect x="38.5" y="726.5" width="421" height="43" rx="0.5" stroke="white" stroke-opacity="0.08" />'
                    '<rect x="38" y="769" width="422" height="83" rx="1" fill="black" /><rect x="38.5" y="769.5" width="421" height="82" rx="0.5" stroke="white" stroke-opacity="0.08" />'
                    '<image transform="translate(200, 200)" href="',
                    zorbRenderer.zorbForAddress(module),
                    '" alt="ZORB" />'
                    '<path d="M248.5 370.5C292.683 370.5 328.5 406.317 328.5 450.5C328.5 494.683 292.683 530.5 248.5 530.5C204.317 530.5 168.5 494.683 168.5 450.5C168.5 406.317 204.317 370.5 248.5 370.5Z" stroke="black" stroke-opacity="0.1" />'
                    '<text class="eyebrow"><tspan x="53" y="708.076">Module</tspan></text><text class="eyebrow"><tspan x="53" y="752.977">Fee</tspan></text><text class="eyebrow"><tspan x="53" y="800.977">Fee Recipient</tspan></text><text text-anchor="end"><tspan x="427" y="708.076">Collection Offers V1.0</tspan></text><text text-anchor="end">',
                    renderFee(fee, feeRecipient)
                )
            );
    }

    function tokenURIForFeeSettings(
        uint256,
        address owner,
        address module,
        uint16 fee,
        address feeRecipient
    ) external returns (string memory) {
        sharedMetadata.encodeMetadataJSON(
            abi.encodePacked(
                '{"name": "Zora Module Fee Settings", "description": "Testing Module BLAH", "image": "data:image/xml+svg;base64,',
                renderSVG(owner, module, fee, feeRecipient),
                '"}'
            )
        );
    }
}
