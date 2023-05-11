// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

const std = @import("std");

/// fixed size ring buffer with stack-like operations
/// pushes always succeed and overite oldest element when full
/// value are not gaurenteed to be contiguous, at
/// worst value will be stored in two contiguos blocks.
/// see `firstSlice()` and `secondSlice()`
pub fn History(comptime T: type, comptime buffer_capacity: usize) type {
    return struct {
        const This = @This();
        pub const capacity = buffer_capacity;

        buffer: [capacity]T = undefined,
        /// next element to write to
        head: usize = 0,
        /// oldest element in buffer
        tail: usize = 0,
        /// empty flag, when head and tail are
        /// equal buffer could be full or empty
        empty: bool = true,

        /// return the number of value
        pub fn size(this: This) usize {
            return if (this.empty)
                0
            else if (this.tail < this.head)
                this.head - this.tail
            else
                capacity - (this.tail - this.head);
        }

        /// push a new value to the end of the buffer
        /// wraps to start of buffer if needed
        /// overwrites oldest element if full
        pub fn push(this: *This, val: T) void {
            this.buffer[this.head] = val;
            const old_head = this.head;
            this.head += 1;
            if (this.head >= capacity)
                this.head = 0;
            if (!this.empty and (this.tail == old_head or (this.tail == capacity and old_head == capacity - 1)))
                this.tail = this.head;
            if (this.empty)
                this.empty = false;
        }

        /// push a new value to the end of the buffer
        /// wraps to start of buffer if needed
        /// does not overwrite oldest element when full
        /// instead, if full `false` is returned
        pub fn pushNoOverwrite(this: *This, val: T) bool {
            if (!this.empty and this.head == this.tail)
                return false;
            this.push(val);
            return true;
        }

        /// removes and returns the last pushed element
        /// if empty returns `null`
        pub fn pop(this: *This) ?T {
            if (this.empty)
                return null;
            if (this.head == 0)
                this.head = capacity;
            this.head -= 1;
            if (this.head == this.tail)
                this.empty = true;
            return this.buffer[this.head];
        }

        /// removes and returns the last pushed element.
        /// appends `val` to beginnig of buffer,
        /// effectivly restoring a previously overritten value
        /// this operation will not change the size of the buffer
        /// if empty returns `null`
        pub fn popRestore(this: *This, val: T) ?T {
            const popped = this.pop();
            this.tail = (this.tail - 1) % capacity;
            this.buffer[this.tail] = val;
            return popped;
        }

        /// get a value from the buffer indexing from tail
        /// eg. `get(0)` will return the oldest value
        /// if empty or out of bounds, returns `null`
        pub fn get(this: This, at: usize) ?T {
            if (this.empty or at >= this.size())
                return null;
            const index = (this.tail + at) % capacity;
            return this.buffer[index];
        }

        /// get a value from the buffer indexing from head
        /// eg. `get(0)` will return the newest value
        /// if empty or out of bounds, returns `null`
        pub fn getFromEnd(this: This, at: usize) ?T {
            if (this.empty or at >= this.size())
                return null;
            const index = if (this.head >= at)
                this.head - at
            else
                capacity - (at - this.head);
            return this.buffer[index];
        }

        /// return the last pushed value
        pub fn top(this: This) ?T {
            if (this.empty)
                return null;
            const index = if (this.head == 0) capacity - 1 else this.head - 1;
            return this.buffer[index];
        }

        /// returns first slice of value
        /// if all value are contiguos this will include
        /// them all, otherwise the rest can be obtained with
        /// `secondSlice()`
        pub fn firstSlice(this: This) []const T {
            const end = if (this.head > this.tail)
                this.head
            else
                capacity;
            return this.buffer[this.tail..end];
        }

        /// returns second slice of value
        /// returns empty slice if all value
        /// are contiguous (head > tail)
        pub fn secondSlice(this: This) []const T {
            if (this.head > this.tail)
                return this.buffer[0..0];
            return this.buffer[0..this.head];
        }
    };
}
