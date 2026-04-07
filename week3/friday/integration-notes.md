# Integration Notes

## Challenge A: ProtectSystem=strict and the EnvironmentFile

### Conflict
The service hardening model required strong filesystem restrictions, but the services also needed to read their environment files correctly at startup. A restrictive service sandbox can block configuration loading if the configuration path is not handled deliberately.

### Options considered
1. Remove the strong filesystem protection from the service.
2. Move all configuration into a different location with looser service restrictions.
3. Keep the hardening in place and explicitly allow read-only access to the configuration path.

### Choice
I kept the stronger filesystem protection and explicitly allowed the service to read the configuration path in a read-only way.

### Why
Dropping the hardening would have weakened the service boundary to solve a narrow access problem. The better design was to preserve the protective control and grant only the minimum access needed for configuration loading. This kept the unit both secure and functional.

---

## Challenge B: The monitoring user and ACL defaults for the health directory

### Conflict
The Friday project introduced a new health artifact directory that was not part of the Tuesday access model. The provisioning process writes the health file as a privileged action, but the result must still be readable by the intended operational identities without being exposed to every user on the server.

### Options considered
1. Leave the health file owned by the privileged writer and require elevated access for reading it.
2. Make the health file broadly readable.
3. Add the health directory to the access model with controlled ownership, permissions, and read access.

### Choice
I added the health directory to the final access model, assigned it controlled ownership, and ensured the generated health artifact was readable to the intended operational identities without making it world-readable.

### Why
This approach preserved least privilege while keeping the health artifact useful. Requiring elevated access for ordinary inspection would have made operations harder, while broad readability would have been unnecessarily permissive.

---

## Challenge C: logrotate postrotate behavior and the logging service

### Conflict
The logrotate configuration needed to ensure that the logging service could continue using rotated files correctly. A common reload pattern is not always appropriate if the service does not actually implement reload semantics or if restart is the safer re-open mechanism.

### Options considered
1. Use a reload action after rotation.
2. Add reload behavior to the service.
3. Use a safe restart pattern in the post-rotation action.

### Choice
I used a safe restart-style post-rotation action for the logging service.

### Why
This was the most reliable option for a simple long-running service in this project. It avoids pretending the service supports a true reload path when restart is the clearer and safer way to ensure file handles are reopened after rotation.

---

## Challenge D: Dirty VM state and package holds

### Conflict
The Friday VM was intentionally not clean. Packages could already be installed, package holds could already exist, and versions could differ from the originally expected pins. A naive provisioning phase could silently downgrade or otherwise alter a system that had already drifted.

### Options considered
1. Force the originally expected package versions every time.
2. Ignore installed versions and accept whatever the machine already had.
3. Check installed versions first, allow matching versions to proceed, and fail loudly on drift instead of silently downgrading.

### Choice
I chose to check installed versions first and fail loudly on unexpected drift rather than downgrade automatically.

### Why
This is the more defensible production behavior. Silent downgrades on a dirty server can hide change-control problems and introduce new risk. A loud failure makes the divergence visible and requires an intentional decision before changing a running system. In practice, I then aligned the pin with the audited VM state so the script could converge the real machine instead of a hypothetical one.

---

## Summary
These four integration points were the places where separate requirements collided: hardening versus readability, artifact generation versus access control, log rotation versus service behavior, and package pinning versus dirty-state reality. The final design resolved each conflict by preserving the stricter control wherever possible and then explicitly allowing only the narrow access or behavior needed to keep the platform operational.