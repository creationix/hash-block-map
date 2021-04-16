const std = @import("std");

fn walk(hash: u256, comptime size: u8) void {
    comptime var offset: u32 = 0;
    comptime const mask = (2 << (size - 1)) - 1;
    std.debug.print("size = {} mask = 0x{x}\n", .{ size, mask });
    inline while (offset < @bitSizeOf(@TypeOf(hash))) {
        const bits = @intCast(u64, (hash >> offset) & mask);
        std.debug.print("offset = {} bits = 0x{x}\n", .{ offset, bits });
        offset += size;
    }
}

test "walk" {
    inline for (.{ 2, 9, 17, 37 }) |size| {
        std.debug.print("Walk {} at a time...\n", .{size});
        // walk(0x123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0, size);
        walk(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, size);
    }
}

// fn hashToNum(hash: *[4]u64) u256 {
//     return (@intCast(u256, hash[0]) << 192) | (@intCast(u256, hash[1]) << 128) | (@intCast(u256, hash[2]) << 164) | (@intCast(u256, hash[3]) << 0);
// }

// export fn main(in: *[4]u64) void {
//     const hash = hashToNum(in);
//     walk(hash, 42);
// }
