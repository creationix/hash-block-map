const std = @import("std");

fn AutoMap(comptime BLOCK_POWER: comptime_int, comptime HASH_POWER: comptime_int) type {
    return struct {
        const BLOCK_SIZE = 2 << (BLOCK_POWER - 1);
        const HASH_SIZE = 2 << (HASH_POWER - 1);
        const BRANCH_POWER = std.math.log2(@sizeOf(Leaf) / @sizeOf(?*u8));
        const BRANCH_FACTOR = 2 << (BRANCH_POWER - 1);
        const Hash = u256;
        const Block = [BLOCK_SIZE]u8;
        const Leaf = struct { block: Block, hash: Hash };
        const Branch = [BRANCH_FACTOR]?*Node;
        const Node = union(enum) { branch: Branch, leaf: Leaf };

        const Map = struct {
            allocator: *std.mem.Allocator,
            root: *Node,
            pub fn init(comptime allocator: *std.mem.Allocator) !Map {
                var root = try allocator.create(Node);
                root.* = .{ .branch = .{null} ** BRANCH_FACTOR };
                return Map{ .allocator = allocator, .root = root };
            }
            pub fn deinit(self: *Map) void {
                const root = self.root;
                self.root.* = undefined;
                self.allocator.destroy(root);
                self.* = undefined;
            }
            pub fn store(self: *Map, block:Block) Hash {
                return 0;
            }
        };
    };
}

// The number of bits consumed per recursion is optimized to be the maximum amount
// that keeps the branch nodes no bigger than the leaf nodes.
test "Proper branch factor" {
    inline for (.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }) |BLOCK_POWER| {
        const Map = AutoMap(BLOCK_POWER, 5);
        // std.debug.print("\nBLOCK_POWER = {}\n", .{BLOCK_POWER});
        // std.debug.print("Map.BLOCK_SIZE = {}\n", .{Map.BLOCK_SIZE});
        // std.debug.print("Map.HASH_SIZE = {}\n", .{Map.HASH_SIZE});
        // std.debug.print("Map.BRANCH_POWER = {}\n", .{Map.BRANCH_POWER});
        // std.debug.print("Map.BRANCH_FACTOR = {}\n", .{Map.BRANCH_FACTOR});
        // std.debug.print("@sizeOf(Map.Hash) = {}\n", .{@sizeOf(Map.Hash)});
        // std.debug.print("@sizeOf(Map.Block) = {}\n", .{@sizeOf(Map.Block)});
        // std.debug.print("@sizeOf(Map.Branch) = {}\n", .{@sizeOf(Map.Branch)});
        // std.debug.print("@sizeOf(Map.Leaf) = {}\n", .{@sizeOf(Map.Leaf)});
        // std.debug.print("@sizeOf(?*Map.Node) = {}\n", .{@sizeOf(?*Map.Node)});
        std.testing.expect(@sizeOf(Map.Branch) <= @sizeOf(Map.Leaf));
    }
}

test "constructor" {
    const Map = AutoMap(12, 5).Map;
    std.debug.print("\nMap = {}\n", .{Map});
    var map = try Map.init(std.testing.allocator);
    // std.debug.print("map = {}\n", .{map});
    map.deinit();
    // map.deinit();
}

// pub fn main() anyerror!void {

//     std.log.info("All your codebase are belong to us.", .{});
// }
