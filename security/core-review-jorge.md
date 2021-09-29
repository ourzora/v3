# Security review: Zora v3 (Core)

---

- **Reviewer**: Jorge Izquierdo
- **Date**: Sept 29th, 2021
- **Source**: [ourzora/v3 @ 374951e](https://github.com/ourzora/v3/tree/374951eea9f14bcfe6d2e4b6781fc8c8c06a4213)
- **Scope**: `contracts/ZoraProposalManager.sol`, `contracts/ZoraModuleApprovalsManager.sol`, `contracts/transferHelpers/*`

---

## 1. `ZoraModuleApprovalsManager`

### 1.1 High severity: Incorrect mapping access in `isModuleApproved`

`userApprovals` mapping was accessed incorrectly with arguments reversed. The reason this wasn't caught was due to the only consumer of this function (`BaseTransferHelper.onlyApprovedModule` modifier) passed the arguments reversed.

**Recommendation**: instead of just testing that the `userApprovals` module has the correct value, also test `isModuleApproved` since that it should be the function to check module approval

**Resultion proposal**: [PR#12](https://github.com/ourzora/v3/pull/12)

### 1.2 Missing functionality: freezing a proposal has no effect on user approvals

Even though frozen state was introduced, there's currently no effect in user approvals

**Resultion proposal**: [PR#12](https://github.com/ourzora/v3/pull/12)

### 1.3 Missing functionality: unused event `AllModulesApprovalSet`

**Resultion proposal**: [PR#12](https://github.com/ourzora/v3/pull/12)

### 1.4 Performance: address arguments in events are not indexed

Currently neither `ModuleApprovalSet` or `AllModulesApprovalSet` use indexed arguments. If they were used, it would allow users to take advantage of bloom filters for faster filtering of events related to their account or a specific module.

**Resultion proposal**: index `address` arguments in both events

## 2. `ZoraProposalManager`

### 2.1 Optimization: check proposal existance using `ProposalStatus`

Currently, all functions check whether a proposal exists by checking whether the proposer address is not the zero address (which it can never be after `proposeModule` since it gets set to `msg.sender`)

However, if all proposals that have been created have a non-zero value in their status (by making `Pending` be the second possible status), all status checks will implictly ensure that the proposal has indeed been created.

**Resultion proposal**: add a `Unexistent` proposal status as the first status option

### 2.x Performance: address arguments in events are not indexed

Similar rational to **1.4**

**Resultion proposal**: index `address` arguments in all events

## 3. `BaseTransferHelper`

### 3.1 High severity: incorrect argument

The other side of issue **1.1**

**Resultion proposal**: [PR#12](https://github.com/ourzora/v3/pull/12)

### 3.x Consistency: Revert reason format unconsistent with general format

**Resultion proposal**: Consider prefixing revert reasons with `BTH::`
