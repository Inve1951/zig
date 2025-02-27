const std = @import("std.zig");
const builtin = @import("builtin");
const root = @import("root");
const c = std.c;

const math = std.math;
const assert = std.debug.assert;
const os = std.os;
const fs = std.fs;
const mem = std.mem;
const meta = std.meta;
const File = std.fs.File;
const Allocator = std.mem.Allocator;

pub const Mode = enum {
    /// I/O operates normally, waiting for the operating system syscalls to complete.
    blocking,

    /// I/O functions are generated async and rely on a global event loop. Event-based I/O.
    evented,
};

const mode = std.options.io_mode;
pub const is_async = mode != .blocking;

/// This is an enum value to use for I/O mode at runtime, since it takes up zero bytes at runtime,
/// and makes expressions comptime-known when `is_async` is `false`.
pub const ModeOverride = if (is_async) Mode else enum { blocking };
pub const default_mode: ModeOverride = if (is_async) Mode.evented else .blocking;

fn getStdOutHandle() os.fd_t {
    if (builtin.os.tag == .windows) {
        if (builtin.zig_backend == .stage2_aarch64) {
            // TODO: this is just a temporary workaround until we advance aarch64 backend further along.
            return os.windows.GetStdHandle(os.windows.STD_OUTPUT_HANDLE) catch os.windows.INVALID_HANDLE_VALUE;
        }
        return os.windows.peb().ProcessParameters.hStdOutput;
    }

    if (@hasDecl(root, "os") and @hasDecl(root.os, "io") and @hasDecl(root.os.io, "getStdOutHandle")) {
        return root.os.io.getStdOutHandle();
    }

    return os.STDOUT_FILENO;
}

/// TODO: async stdout on windows without a dedicated thread.
/// https://github.com/ziglang/zig/pull/4816#issuecomment-604521023
pub fn getStdOut() File {
    return File{
        .handle = getStdOutHandle(),
        .capable_io_mode = .blocking,
        .intended_io_mode = default_mode,
    };
}

fn getStdErrHandle() os.fd_t {
    if (builtin.os.tag == .windows) {
        if (builtin.zig_backend == .stage2_aarch64) {
            // TODO: this is just a temporary workaround until we advance aarch64 backend further along.
            return os.windows.GetStdHandle(os.windows.STD_ERROR_HANDLE) catch os.windows.INVALID_HANDLE_VALUE;
        }
        return os.windows.peb().ProcessParameters.hStdError;
    }

    if (@hasDecl(root, "os") and @hasDecl(root.os, "io") and @hasDecl(root.os.io, "getStdErrHandle")) {
        return root.os.io.getStdErrHandle();
    }

    return os.STDERR_FILENO;
}

/// This returns a `File` that is configured to block with every write, in order
/// to facilitate better debugging. This can be changed by modifying the `intended_io_mode` field.
pub fn getStdErr() File {
    return File{
        .handle = getStdErrHandle(),
        .capable_io_mode = .blocking,
        .intended_io_mode = .blocking,
    };
}

fn getStdInHandle() os.fd_t {
    if (builtin.os.tag == .windows) {
        if (builtin.zig_backend == .stage2_aarch64) {
            // TODO: this is just a temporary workaround until we advance aarch64 backend further along.
            return os.windows.GetStdHandle(os.windows.STD_INPUT_HANDLE) catch os.windows.INVALID_HANDLE_VALUE;
        }
        return os.windows.peb().ProcessParameters.hStdInput;
    }

    if (@hasDecl(root, "os") and @hasDecl(root.os, "io") and @hasDecl(root.os.io, "getStdInHandle")) {
        return root.os.io.getStdInHandle();
    }

    return os.STDIN_FILENO;
}

/// TODO: async stdin on windows without a dedicated thread.
/// https://github.com/ziglang/zig/pull/4816#issuecomment-604521023
pub fn getStdIn() File {
    return File{
        .handle = getStdInHandle(),
        .capable_io_mode = .blocking,
        .intended_io_mode = default_mode,
    };
}

pub fn GenericReader(
    comptime Context: type,
    comptime ReadError: type,
    /// Returns the number of bytes read. It may be less than buffer.len.
    /// If the number of bytes read is 0, it means end of stream.
    /// End of stream is not an error condition.
    comptime readFn: fn (context: Context, buffer: []u8) ReadError!usize,
) type {
    return struct {
        context: Context,

        pub const Error = ReadError;
        pub const NoEofError = ReadError || error{
            EndOfStream,
        };

        pub inline fn read(self: Self, buffer: []u8) Error!usize {
            return readFn(self.context, buffer);
        }

        pub inline fn readAll(self: Self, buffer: []u8) Error!usize {
            return @errorCast(self.any().readAll(buffer));
        }

        pub inline fn readAtLeast(self: Self, buffer: []u8, len: usize) Error!usize {
            return @errorCast(self.any().readAtLeast(buffer, len));
        }

        pub inline fn readNoEof(self: Self, buf: []u8) NoEofError!void {
            return @errorCast(self.any().readNoEof(buf));
        }

        pub inline fn readAllArrayList(
            self: Self,
            array_list: *std.ArrayList(u8),
            max_append_size: usize,
        ) (error{StreamTooLong} || Allocator.Error || Error)!void {
            return @errorCast(self.any().readAllArrayList(array_list, max_append_size));
        }

        pub inline fn readAllArrayListAligned(
            self: Self,
            comptime alignment: ?u29,
            array_list: *std.ArrayListAligned(u8, alignment),
            max_append_size: usize,
        ) (error{StreamTooLong} || Allocator.Error || Error)!void {
            return @errorCast(self.any().readAllArrayListAligned(
                alignment,
                array_list,
                max_append_size,
            ));
        }

        pub inline fn readAllAlloc(
            self: Self,
            allocator: Allocator,
            max_size: usize,
        ) (Error || Allocator.Error || error{StreamTooLong})![]u8 {
            return @errorCast(self.any().readAllAlloc(allocator, max_size));
        }

        pub inline fn readUntilDelimiterArrayList(
            self: Self,
            array_list: *std.ArrayList(u8),
            delimiter: u8,
            max_size: usize,
        ) (NoEofError || Allocator.Error || error{StreamTooLong})!void {
            return @errorCast(self.any().readUntilDelimiterArrayList(
                array_list,
                delimiter,
                max_size,
            ));
        }

        pub inline fn readUntilDelimiterAlloc(
            self: Self,
            allocator: Allocator,
            delimiter: u8,
            max_size: usize,
        ) (NoEofError || Allocator.Error || error{StreamTooLong})![]u8 {
            return @errorCast(self.any().readUntilDelimiterAlloc(
                allocator,
                delimiter,
                max_size,
            ));
        }

        pub inline fn readUntilDelimiter(
            self: Self,
            buf: []u8,
            delimiter: u8,
        ) (NoEofError || error{StreamTooLong})![]u8 {
            return @errorCast(self.any().readUntilDelimiter(buf, delimiter));
        }

        pub inline fn readUntilDelimiterOrEofAlloc(
            self: Self,
            allocator: Allocator,
            delimiter: u8,
            max_size: usize,
        ) (Error || Allocator.Error || error{StreamTooLong})!?[]u8 {
            return @errorCast(self.any().readUntilDelimiterOrEofAlloc(
                allocator,
                delimiter,
                max_size,
            ));
        }

        pub inline fn readUntilDelimiterOrEof(
            self: Self,
            buf: []u8,
            delimiter: u8,
        ) (Error || error{StreamTooLong})!?[]u8 {
            return @errorCast(self.any().readUntilDelimiterOrEof(buf, delimiter));
        }

        pub inline fn streamUntilDelimiter(
            self: Self,
            writer: anytype,
            delimiter: u8,
            optional_max_size: ?usize,
        ) (NoEofError || error{StreamTooLong} || @TypeOf(writer).Error)!void {
            return @errorCast(self.any().streamUntilDelimiter(
                writer,
                delimiter,
                optional_max_size,
            ));
        }

        pub inline fn skipUntilDelimiterOrEof(self: Self, delimiter: u8) Error!void {
            return @errorCast(self.any().skipUntilDelimiterOrEof(delimiter));
        }

        pub inline fn readByte(self: Self) NoEofError!u8 {
            return @errorCast(self.any().readByte());
        }

        pub inline fn readByteSigned(self: Self) NoEofError!i8 {
            return @errorCast(self.any().readByteSigned());
        }

        pub inline fn readBytesNoEof(
            self: Self,
            comptime num_bytes: usize,
        ) NoEofError![num_bytes]u8 {
            return @errorCast(self.any().readBytesNoEof(num_bytes));
        }

        pub inline fn readIntoBoundedBytes(
            self: Self,
            comptime num_bytes: usize,
            bounded: *std.BoundedArray(u8, num_bytes),
        ) Error!void {
            return @errorCast(self.any().readIntoBoundedBytes(num_bytes, bounded));
        }

        pub inline fn readBoundedBytes(
            self: Self,
            comptime num_bytes: usize,
        ) Error!std.BoundedArray(u8, num_bytes) {
            return @errorCast(self.any().readBoundedBytes(num_bytes));
        }

        pub inline fn readInt(self: Self, comptime T: type, endian: std.builtin.Endian) NoEofError!T {
            return @errorCast(self.any().readInt(T, endian));
        }

        pub inline fn readVarInt(
            self: Self,
            comptime ReturnType: type,
            endian: std.builtin.Endian,
            size: usize,
        ) NoEofError!ReturnType {
            return @errorCast(self.any().readVarInt(ReturnType, endian, size));
        }

        pub const SkipBytesOptions = AnyReader.SkipBytesOptions;

        pub inline fn skipBytes(
            self: Self,
            num_bytes: u64,
            comptime options: SkipBytesOptions,
        ) NoEofError!void {
            return @errorCast(self.any().skipBytes(num_bytes, options));
        }

        pub inline fn isBytes(self: Self, slice: []const u8) NoEofError!bool {
            return @errorCast(self.any().isBytes(slice));
        }

        pub inline fn readStruct(self: Self, comptime T: type) NoEofError!T {
            return @errorCast(self.any().readStruct(T));
        }

        pub inline fn readStructEndian(self: Self, comptime T: type, endian: std.builtin.Endian) NoEofError!T {
            return @errorCast(self.any().readStructEndian(T, endian));
        }

        pub const ReadEnumError = NoEofError || error{
            /// An integer was read, but it did not match any of the tags in the supplied enum.
            InvalidValue,
        };

        pub inline fn readEnum(
            self: Self,
            comptime Enum: type,
            endian: std.builtin.Endian,
        ) ReadEnumError!Enum {
            return @errorCast(self.any().readEnum(Enum, endian));
        }

        pub inline fn any(self: *const Self) AnyReader {
            return .{
                .context = @ptrCast(&self.context),
                .readFn = typeErasedReadFn,
            };
        }

        const Self = @This();

        fn typeErasedReadFn(context: *const anyopaque, buffer: []u8) anyerror!usize {
            const ptr: *const Context = @alignCast(@ptrCast(context));
            return readFn(ptr.*, buffer);
        }
    };
}

pub fn GenericWriter(
    comptime Context: type,
    comptime WriteError: type,
    comptime writeFn: fn (context: Context, bytes: []const u8) WriteError!usize,
) type {
    return struct {
        context: Context,

        const Self = @This();
        pub const Error = WriteError;

        pub inline fn write(self: Self, bytes: []const u8) Error!usize {
            return writeFn(self.context, bytes);
        }

        pub inline fn writeAll(self: Self, bytes: []const u8) Error!void {
            return @errorCast(self.any().writeAll(bytes));
        }

        pub inline fn print(self: Self, comptime format: []const u8, args: anytype) Error!void {
            return @errorCast(self.any().print(format, args));
        }

        pub inline fn writeByte(self: Self, byte: u8) Error!void {
            return @errorCast(self.any().writeByte(byte));
        }

        pub inline fn writeByteNTimes(self: Self, byte: u8, n: usize) Error!void {
            return @errorCast(self.any().writeByteNTimes(byte, n));
        }

        pub inline fn writeBytesNTimes(self: Self, bytes: []const u8, n: usize) Error!void {
            return @errorCast(self.any().writeBytesNTimes(bytes, n));
        }

        pub inline fn writeInt(self: Self, comptime T: type, value: T, endian: std.builtin.Endian) Error!void {
            return @errorCast(self.any().writeInt(T, value, endian));
        }

        pub inline fn writeStruct(self: Self, value: anytype) Error!void {
            return @errorCast(self.any().writeStruct(value));
        }

        pub inline fn any(self: *const Self) AnyWriter {
            return .{
                .context = @ptrCast(&self.context),
                .writeFn = typeErasedWriteFn,
            };
        }

        fn typeErasedWriteFn(context: *const anyopaque, bytes: []const u8) anyerror!usize {
            const ptr: *const Context = @alignCast(@ptrCast(context));
            return writeFn(ptr.*, bytes);
        }
    };
}

/// Deprecated; consider switching to `AnyReader` or use `GenericReader`
/// to use previous API.
pub const Reader = GenericReader;
/// Deprecated; consider switching to `AnyWriter` or use `GenericWriter`
/// to use previous API.
pub const Writer = GenericWriter;

pub const AnyReader = @import("io/Reader.zig");
pub const AnyWriter = @import("io/Writer.zig");

pub const SeekableStream = @import("io/seekable_stream.zig").SeekableStream;

pub const BufferedWriter = @import("io/buffered_writer.zig").BufferedWriter;
pub const bufferedWriter = @import("io/buffered_writer.zig").bufferedWriter;

pub const BufferedReader = @import("io/buffered_reader.zig").BufferedReader;
pub const bufferedReader = @import("io/buffered_reader.zig").bufferedReader;
pub const bufferedReaderSize = @import("io/buffered_reader.zig").bufferedReaderSize;

pub const PeekStream = @import("io/peek_stream.zig").PeekStream;
pub const peekStream = @import("io/peek_stream.zig").peekStream;

pub const FixedBufferStream = @import("io/fixed_buffer_stream.zig").FixedBufferStream;
pub const fixedBufferStream = @import("io/fixed_buffer_stream.zig").fixedBufferStream;

pub const CWriter = @import("io/c_writer.zig").CWriter;
pub const cWriter = @import("io/c_writer.zig").cWriter;

pub const LimitedReader = @import("io/limited_reader.zig").LimitedReader;
pub const limitedReader = @import("io/limited_reader.zig").limitedReader;

pub const CountingWriter = @import("io/counting_writer.zig").CountingWriter;
pub const countingWriter = @import("io/counting_writer.zig").countingWriter;
pub const CountingReader = @import("io/counting_reader.zig").CountingReader;
pub const countingReader = @import("io/counting_reader.zig").countingReader;

pub const MultiWriter = @import("io/multi_writer.zig").MultiWriter;
pub const multiWriter = @import("io/multi_writer.zig").multiWriter;

pub const BitReader = @import("io/bit_reader.zig").BitReader;
pub const bitReader = @import("io/bit_reader.zig").bitReader;

pub const BitWriter = @import("io/bit_writer.zig").BitWriter;
pub const bitWriter = @import("io/bit_writer.zig").bitWriter;

pub const ChangeDetectionStream = @import("io/change_detection_stream.zig").ChangeDetectionStream;
pub const changeDetectionStream = @import("io/change_detection_stream.zig").changeDetectionStream;

pub const FindByteWriter = @import("io/find_byte_writer.zig").FindByteWriter;
pub const findByteWriter = @import("io/find_byte_writer.zig").findByteWriter;

pub const BufferedAtomicFile = @import("io/buffered_atomic_file.zig").BufferedAtomicFile;

pub const StreamSource = @import("io/stream_source.zig").StreamSource;

pub const tty = @import("io/tty.zig");

/// A Writer that doesn't write to anything.
pub const null_writer = @as(NullWriter, .{ .context = {} });

const NullWriter = Writer(void, error{}, dummyWrite);
fn dummyWrite(context: void, data: []const u8) error{}!usize {
    _ = context;
    return data.len;
}

test "null_writer" {
    null_writer.writeAll("yay" ** 10) catch |err| switch (err) {};
}

pub fn poll(
    allocator: Allocator,
    comptime StreamEnum: type,
    files: PollFiles(StreamEnum),
) Poller(StreamEnum) {
    const enum_fields = @typeInfo(StreamEnum).Enum.fields;
    var result: Poller(StreamEnum) = undefined;

    if (builtin.os.tag == .windows) result.windows = .{
        .first_read_done = false,
        .overlapped = [1]os.windows.OVERLAPPED{
            mem.zeroes(os.windows.OVERLAPPED),
        } ** enum_fields.len,
        .active = .{
            .count = 0,
            .handles_buf = undefined,
            .stream_map = undefined,
        },
    };

    inline for (0..enum_fields.len) |i| {
        result.fifos[i] = .{
            .allocator = allocator,
            .buf = &.{},
            .head = 0,
            .count = 0,
        };
        if (builtin.os.tag == .windows) {
            result.windows.active.handles_buf[i] = @field(files, enum_fields[i].name).handle;
        } else {
            result.poll_fds[i] = .{
                .fd = @field(files, enum_fields[i].name).handle,
                .events = os.POLL.IN,
                .revents = undefined,
            };
        }
    }
    return result;
}

pub const PollFifo = std.fifo.LinearFifo(u8, .Dynamic);

pub fn Poller(comptime StreamEnum: type) type {
    return struct {
        const enum_fields = @typeInfo(StreamEnum).Enum.fields;
        const PollFd = if (builtin.os.tag == .windows) void else std.os.pollfd;

        fifos: [enum_fields.len]PollFifo,
        poll_fds: [enum_fields.len]PollFd,
        windows: if (builtin.os.tag == .windows) struct {
            first_read_done: bool,
            overlapped: [enum_fields.len]os.windows.OVERLAPPED,
            active: struct {
                count: math.IntFittingRange(0, enum_fields.len),
                handles_buf: [enum_fields.len]os.windows.HANDLE,
                stream_map: [enum_fields.len]StreamEnum,

                pub fn removeAt(self: *@This(), index: u32) void {
                    std.debug.assert(index < self.count);
                    for (index + 1..self.count) |i| {
                        self.handles_buf[i - 1] = self.handles_buf[i];
                        self.stream_map[i - 1] = self.stream_map[i];
                    }
                    self.count -= 1;
                }
            },
        } else void,

        const Self = @This();

        pub fn deinit(self: *Self) void {
            if (builtin.os.tag == .windows) {
                // cancel any pending IO to prevent clobbering OVERLAPPED value
                for (self.windows.active.handles_buf[0..self.windows.active.count]) |h| {
                    _ = os.windows.kernel32.CancelIo(h);
                }
            }
            inline for (&self.fifos) |*q| q.deinit();
            self.* = undefined;
        }

        pub fn poll(self: *Self) !bool {
            if (builtin.os.tag == .windows) {
                return pollWindows(self);
            } else {
                return pollPosix(self);
            }
        }

        pub inline fn fifo(self: *Self, comptime which: StreamEnum) *PollFifo {
            return &self.fifos[@intFromEnum(which)];
        }

        fn pollWindows(self: *Self) !bool {
            const bump_amt = 512;

            if (!self.windows.first_read_done) {
                // Windows Async IO requires an initial call to ReadFile before waiting on the handle
                for (0..enum_fields.len) |i| {
                    const handle = self.windows.active.handles_buf[i];
                    switch (try windowsAsyncRead(
                        handle,
                        &self.windows.overlapped[i],
                        &self.fifos[i],
                        bump_amt,
                    )) {
                        .pending => {
                            self.windows.active.handles_buf[self.windows.active.count] = handle;
                            self.windows.active.stream_map[self.windows.active.count] = @as(StreamEnum, @enumFromInt(i));
                            self.windows.active.count += 1;
                        },
                        .closed => {}, // don't add to the wait_objects list
                    }
                }
                self.windows.first_read_done = true;
            }

            while (true) {
                if (self.windows.active.count == 0) return false;

                const status = os.windows.kernel32.WaitForMultipleObjects(
                    self.windows.active.count,
                    &self.windows.active.handles_buf,
                    0,
                    os.windows.INFINITE,
                );
                if (status == os.windows.WAIT_FAILED)
                    return os.windows.unexpectedError(os.windows.kernel32.GetLastError());

                if (status < os.windows.WAIT_OBJECT_0 or status > os.windows.WAIT_OBJECT_0 + enum_fields.len - 1)
                    unreachable;

                const active_idx = status - os.windows.WAIT_OBJECT_0;

                const handle = self.windows.active.handles_buf[active_idx];
                const stream_idx = @intFromEnum(self.windows.active.stream_map[active_idx]);
                var read_bytes: u32 = undefined;
                if (0 == os.windows.kernel32.GetOverlappedResult(
                    handle,
                    &self.windows.overlapped[stream_idx],
                    &read_bytes,
                    0,
                )) switch (os.windows.kernel32.GetLastError()) {
                    .BROKEN_PIPE => {
                        self.windows.active.removeAt(active_idx);
                        continue;
                    },
                    else => |err| return os.windows.unexpectedError(err),
                };

                self.fifos[stream_idx].update(read_bytes);

                switch (try windowsAsyncRead(
                    handle,
                    &self.windows.overlapped[stream_idx],
                    &self.fifos[stream_idx],
                    bump_amt,
                )) {
                    .pending => {},
                    .closed => self.windows.active.removeAt(active_idx),
                }
                return true;
            }
        }

        fn pollPosix(self: *Self) !bool {
            // We ask for ensureUnusedCapacity with this much extra space. This
            // has more of an effect on small reads because once the reads
            // start to get larger the amount of space an ArrayList will
            // allocate grows exponentially.
            const bump_amt = 512;

            const err_mask = os.POLL.ERR | os.POLL.NVAL | os.POLL.HUP;

            const events_len = try os.poll(&self.poll_fds, std.math.maxInt(i32));
            if (events_len == 0) {
                for (self.poll_fds) |poll_fd| {
                    if (poll_fd.fd != -1) return true;
                } else return false;
            }

            var keep_polling = false;
            inline for (&self.poll_fds, &self.fifos) |*poll_fd, *q| {
                // Try reading whatever is available before checking the error
                // conditions.
                // It's still possible to read after a POLL.HUP is received,
                // always check if there's some data waiting to be read first.
                if (poll_fd.revents & os.POLL.IN != 0) {
                    const buf = try q.writableWithSize(bump_amt);
                    const amt = try os.read(poll_fd.fd, buf);
                    q.update(amt);
                    if (amt == 0) {
                        // Remove the fd when the EOF condition is met.
                        poll_fd.fd = -1;
                    } else {
                        keep_polling = true;
                    }
                } else if (poll_fd.revents & err_mask != 0) {
                    // Exclude the fds that signaled an error.
                    poll_fd.fd = -1;
                } else if (poll_fd.fd != -1) {
                    keep_polling = true;
                }
            }
            return keep_polling;
        }
    };
}

fn windowsAsyncRead(
    handle: os.windows.HANDLE,
    overlapped: *os.windows.OVERLAPPED,
    fifo: *PollFifo,
    bump_amt: usize,
) !enum { pending, closed } {
    while (true) {
        const buf = try fifo.writableWithSize(bump_amt);
        var read_bytes: u32 = undefined;
        const read_result = os.windows.kernel32.ReadFile(handle, buf.ptr, math.cast(u32, buf.len) orelse math.maxInt(u32), &read_bytes, overlapped);
        if (read_result == 0) return switch (os.windows.kernel32.GetLastError()) {
            .IO_PENDING => .pending,
            .BROKEN_PIPE => .closed,
            else => |err| os.windows.unexpectedError(err),
        };
        fifo.update(read_bytes);
    }
}

/// Given an enum, returns a struct with fields of that enum, each field
/// representing an I/O stream for polling.
pub fn PollFiles(comptime StreamEnum: type) type {
    const enum_fields = @typeInfo(StreamEnum).Enum.fields;
    var struct_fields: [enum_fields.len]std.builtin.Type.StructField = undefined;
    for (&struct_fields, enum_fields) |*struct_field, enum_field| {
        struct_field.* = .{
            .name = enum_field.name ++ "",
            .type = fs.File,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(fs.File),
        };
    }
    return @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = &struct_fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

test {
    _ = AnyReader;
    _ = AnyWriter;
    _ = @import("io/bit_reader.zig");
    _ = @import("io/bit_writer.zig");
    _ = @import("io/buffered_atomic_file.zig");
    _ = @import("io/buffered_reader.zig");
    _ = @import("io/buffered_writer.zig");
    _ = @import("io/c_writer.zig");
    _ = @import("io/counting_writer.zig");
    _ = @import("io/counting_reader.zig");
    _ = @import("io/fixed_buffer_stream.zig");
    _ = @import("io/peek_stream.zig");
    _ = @import("io/seekable_stream.zig");
    _ = @import("io/stream_source.zig");
    _ = @import("io/test.zig");
}
