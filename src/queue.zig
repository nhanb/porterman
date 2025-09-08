const std = @import("std");
const t = std.testing;

/// Very simple thread-safe, allocation-free ring buffer
pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        data: [capacity]T = undefined,
        pop_idx: usize = 0,
        push_idx: usize = 0,

        mutex: std.Thread.Mutex = .{},

        pub fn push(self: *@This(), item: T) ?bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.isFull()) {
                return null;
            }
            const index = self.push_idx % capacity;
            self.data[index] = item;
            self.push_idx += 1;
            return true;
        }

        pub fn pop(self: *@This()) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.isEmpty()) {
                return null;
            }
            const index = self.pop_idx % capacity;
            self.pop_idx += 1;
            return self.data[index];
        }

        fn mask(self: *@This(), index: usize) usize {
            return index % self.data.len;
        }

        fn mask2(self: *@This(), index: usize) usize {
            return index % (self.data.len * 2);
        }

        fn isEmpty(self: *@This()) bool {
            return self.push_idx == self.pop_idx;
        }

        fn isFull(self: *@This()) bool {
            return self.mask2(self.push_idx + self.data.len) == self.pop_idx;
        }
    };
}

test "RingBuffer" {
    var rb = RingBuffer(i64, 5){};
    try t.expectEqual(null, rb.pop());
    //try t.expectEqual(0, rb.num_filled());
    //try t.expectEqual(5, rb.num_available());

    _ = rb.push(50);
    _ = rb.push(51);
    _ = rb.push(52);

    try t.expectEqual(50, rb.pop());
    try t.expectEqual(51, rb.pop());

    _ = rb.push(53);
    _ = rb.push(54);
    _ = rb.push(55);
    _ = rb.push(56);
    try t.expectEqual(null, rb.push(57));

    try t.expectEqual(52, rb.pop());
    try t.expectEqual(53, rb.pop());
    try t.expectEqual(54, rb.pop());
    try t.expectEqual(55, rb.pop());
    try t.expectEqual(56, rb.pop());
}
