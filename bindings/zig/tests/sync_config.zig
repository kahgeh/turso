const std = @import("std");
const turso = @import("turso");

test "raw sync ABI is imported" {
    var config: turso.raw_sync.turso_sync_database_config_t = undefined;
    config.bootstrap_if_empty = true;
    try std.testing.expect(config.bootstrap_if_empty);
    _ = turso.raw_sync.turso_sync_database_new;
}

test "remote encryption cipher reserved bytes match Rust binding" {
    try std.testing.expectEqual(@as(i32, 28), turso.sync.RemoteEncryptionCipher.aes_256_gcm.reservedBytes());
    try std.testing.expectEqual(@as(i32, 28), turso.sync.RemoteEncryptionCipher.aes_128_gcm.reservedBytes());
    try std.testing.expectEqual(@as(i32, 28), turso.sync.RemoteEncryptionCipher.chacha20_poly1305.reservedBytes());
    try std.testing.expectEqual(@as(i32, 32), turso.sync.RemoteEncryptionCipher.aegis_128l.reservedBytes());
    try std.testing.expectEqual(@as(i32, 32), turso.sync.RemoteEncryptionCipher.aegis_128x2.reservedBytes());
    try std.testing.expectEqual(@as(i32, 32), turso.sync.RemoteEncryptionCipher.aegis_128x4.reservedBytes());
    try std.testing.expectEqual(@as(i32, 48), turso.sync.RemoteEncryptionCipher.aegis_256.reservedBytes());
    try std.testing.expectEqual(@as(i32, 48), turso.sync.RemoteEncryptionCipher.aegis_256x2.reservedBytes());
    try std.testing.expectEqual(@as(i32, 48), turso.sync.RemoteEncryptionCipher.aegis_256x4.reservedBytes());
}

test "builder forwards sync config defaults and remote encryption" {
    const builder = turso.sync.Builder.newRemote(std.testing.allocator, "local.db")
        .withRemoteUrl("libsql://example.turso.io")
        .withAuthToken("secret-token")
        .withRemoteEncryption("base64-key", .aegis_256x4)
        .withPartialSyncOptsExperimental(.{
        .strategy = .{ .query = "SELECT * FROM t" },
        .segment_size = 4096,
        .prefetch = true,
    });

    try std.testing.expectEqualStrings("local.db", builder.db_config.path);
    try std.testing.expectEqualStrings("local.db", builder.sync_config.path);
    try std.testing.expectEqualStrings("turso-sync-zig", builder.sync_config.client_name);
    try std.testing.expect(builder.sync_config.bootstrap_if_empty);
    try std.testing.expectEqualStrings("secret-token", builder.auth_token.?);
    try std.testing.expectEqual(@as(i32, 48), builder.sync_config.reserved_bytes);
    try std.testing.expectEqualStrings("base64-key", builder.sync_config.remote_encryption_key.?);
    try std.testing.expectEqualStrings("aegis256x4", builder.sync_config.remote_encryption_cipher.?);
    try std.testing.expectEqual(@as(usize, 4096), builder.sync_config.partial_sync_opts.?.segment_size);
}
