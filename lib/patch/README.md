# Rewindable Security Patches

**Philosophy**: All security actions should be reversible to enable safe testing and experimentation.

## Structure

### `patches/` - Rewindable Security Actions
Contains patch scripts that implement security measures with full backup/restore capability.

### `backups/` - System State Backups  
Contains timestamped backups of system state before patches are applied.

## Patch Pattern

Every patch script implements the following interface:

```bash
./patch_name.sh status    # Check if patch is applied
./patch_name.sh patch     # Apply patch (creates backup)
./patch_name.sh unpatch   # Restore from backup  
./patch_name.sh test      # Test functionality after patch
./patch_name.sh logs      # Show relevant logs/monitoring
```

## Safety Protocol

1. **Always backup** before making changes
2. **Test functionality** after applying patches  
3. **Monitor logs** to verify no breakage
4. **Document findings** for permanent implementation
5. **Revert if issues** detected during testing

## Example Workflow

```bash
# Check current state
lib/patch/patches/google_telemetry_block.sh status

# Apply security patch with backup
lib/patch/patches/google_telemetry_block.sh patch

# Test that target application still works
lib/patch/patches/google_telemetry_block.sh test

# Monitor logs in separate terminal
lib/patch/patches/google_telemetry_block.sh logs

# If all good, document findings
# If problems detected, revert
lib/patch/patches/google_telemetry_block.sh unpatch
```

## Integration with Security Tools

- **Snoopy** uses patches for evidence-based defensive actions
- **Security agents** can safely test defensive measures
- **Investigation workflow** allows hypothesis testing with rollback
- **Production deployment** only after thorough patch testing