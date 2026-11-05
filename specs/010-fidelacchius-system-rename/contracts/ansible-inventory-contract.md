# Contract: Ansible Infrastructure as Code Inventory

**Contract ID**: `ANSIBLE-INVENTORY-V1`  
**Feature**: `010-fidelacchius-system-rename`  
**Status**: Active  

---

## 1. Inventory Host Schema (`ansible/inventory/hosts.yml`)

The primary node MUST be declared under the canonical name `fidelacchius`:

```yaml
---
all:
  children:
    homelab_nodes:
      hosts:
        fidelacchius:
          ansible_host: 192.168.4.57
          ansible_user: admin
          ansible_python_interpreter: /usr/local/bin/python3
    arch_linux:
      hosts:
        fidelacchius:
```

---

## 2. Host Variables Hierarchy

- **Host Variables Directory**: `ansible/inventory/host_vars/fidelacchius/`
- **Required Files**:
  - `storage.yml`: Storage layout, disk UUID mappings, mergerfs, and snapraid declarations.

---

## 3. Operator Execution Contract

- Running Ansible playbooks locally or remotely targeting `fidelacchius` MUST succeed without inventory resolution warnings or missing variable errors:
  ```bash
  ansible-playbook -i inventory/hosts.yml playbooks/site.yml --limit fidelacchius --check
  ```
- Shell and PowerShell operator helpers (`scripts/apply-*.sh`, `scripts/apply-*.ps1`, `scripts/verify-*.sh`, `scripts/verify-*.ps1`) MUST default their target node identifier or banner output to `fidelacchius`.
