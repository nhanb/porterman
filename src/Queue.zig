//! Thread-safe FIFO queue
const std = @import("std");
const t = std.testing;

//pub fn init(comptime Message: type) type {
//    return struct {
//        mutex: std.Thread.Mutex = .{},
//        condition: std.Thread.Condition = .{},
//        messages: std.ArrayList(Message) = .{},
//
//        pub fn pop(self: *@This()) Message {
//            self.mutex.lock();
//            defer self.mutex.unlock();
//
//            if (self.messages.items.len == 0) {
//                self.condition.wait(&self.mutex);
//            }
//
//            // TODO
//        }
//
//        pub fn push(self: *@This(), message: Message) Message {
//            _ = message;
//            {
//                self.mutex.lock();
//                defer self.mutex.unlock();
//                self.predicate = true;
//            }
//            self.condition.signal();
//        }
//    };
//}

/// Very simple ring buffer that can process up to <usize> items,
/// which means 2^64 on 64bit machines.
pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        buffer: [capacity]T = undefined,
        pop_cursor: usize = 0,
        push_cursor: usize = 0,

        pub fn push(self: *@This(), item: T) !void {
            if (self.num_available() == 0) {
                return error.BufferFull;
            }
            const index = self.push_cursor % capacity;
            self.buffer[index] = item;
            self.push_cursor += 1;
        }

        pub fn pop(self: *@This()) !T {
            if (self.num_filled() == 0) {
                return error.BufferEmpty;
            }
            const index = self.pop_cursor % capacity;
            self.pop_cursor += 1;
            return self.buffer[index];
        }

        pub fn num_available(self: *@This()) usize {
            return self.buffer.len - (self.push_cursor - self.pop_cursor);
        }

        pub fn num_filled(self: *@This()) usize {
            return self.push_cursor - self.pop_cursor;
        }
    };
}

test "RingBuffer" {
    var rb = RingBuffer(i64, 5){};
    try t.expectEqual(error.BufferEmpty, rb.pop());
    try t.expectEqual(0, rb.num_filled());
    try t.expectEqual(5, rb.num_available());

    try rb.push(50);
    try rb.push(51);
    try rb.push(52);
    try t.expectEqual(3, rb.num_filled());
    try t.expectEqual(2, rb.num_available());

    try t.expectEqual(50, try rb.pop());
    try t.expectEqual(51, try rb.pop());
    try t.expectEqual(1, rb.num_filled());
    try t.expectEqual(4, rb.num_available());

    try rb.push(53);
    try rb.push(54);
    try rb.push(55);
    try rb.push(56);
    try t.expectEqual(error.BufferFull, rb.push(57));
    try t.expectEqual(5, rb.num_filled());
    try t.expectEqual(0, rb.num_available());

    try t.expectEqual(52, try rb.pop());
    try t.expectEqual(53, try rb.pop());
    try t.expectEqual(54, try rb.pop());
    try t.expectEqual(55, try rb.pop());
    try t.expectEqual(56, try rb.pop());
    try t.expectEqual(error.BufferEmpty, rb.pop());
}
