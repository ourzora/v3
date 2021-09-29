# Security review: Zora v3 (Core)

---

- **Reviewer**: Jorge Izquierdo
- **Date**: Sept 29th, 2021
- **Source**: [ourzora/v3 @ 374951e](https://github.com/ourzora/v3/tree/374951eea9f14bcfe6d2e4b6781fc8c8c06a4213)
- **Scope**: `contracts/ZoraProposalManager.sol`, `contracts/ZoraModuleApprovalsManager.sol`, `contracts/transferHelpers/*`

---

## 1. `ZoraModuleApprovalsManager`

### 1.1 Missing functionality: freezing a proposal has no effect on user approvals

Even though frozen state was introduced, there's currently no effect in user approvals

Resultion proposal: [PR#12](https://github.com/ourzora/v3/pull/12)

### 1.2 Missing functionality: unused event `AllModulesApprovalSet`

Resultion proposal: [PR#12](https://github.com/ourzora/v3/pull/12)

## 3. `BaseTransferHelper`

### 3.x Consistency: Revert reason format unconsistent with general format

Resolution: Consider prefixing revert reasons with `BTH::`
