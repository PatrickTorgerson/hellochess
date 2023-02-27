// ********************************************************************************
//* https://github.com/PatrickTorgerson/hellochess
//* Copyright (c) 2022 Patrick Torgerson
//* MIT license, see LICENSE for more information
// ********************************************************************************

//! internal struct representing a parsed PGN move

const std = @import("std");

const Piece = @import("Piece.zig");
const Class = Piece.Class;
const Affiliation = Piece.Affiliation;

const types = @import("types.zig");
const Square = types.Square;
const Coordinate = types.Coordinate;
const Move = types.Move;
const MoveResult = types.MoveResult;

const Notation = @This();

class: Class = .pawn,
source_file: ?i8 = null,
source_rank: ?i8 = null,
destination: Coordinate = Coordinate.from_string("a1"),
promote_to: ?Class = null,
expect_capture: bool = false,
castle_kingside: ?bool = null,

/// parse move notation
/// uses standard PGN chess notation (https://en.wikipedia.org/wiki/Algebraic_notation_(chess))
/// returns null if notation is invalid
pub fn parse(move_notation: []const u8) ?Notation {
    // "([NBRQK]?[a-h]?[1-8]?x?[a-h][1-8](=[NBRQ])?[+#]?)|O-O|O-O-O|0-0|0-0-0"

    var parsed = Notation{};
    var move: []const u8 = move_notation;

    if (move.len < 2) return null;

    if (std.mem.eql(u8, move, "O-O")) {
        parsed.castle_kingside = true;
        return parsed;
    }
    else if (std.mem.eql(u8, move, "0-0")) {
        parsed.castle_kingside = true;
        return parsed;
    }
    else if (std.mem.eql(u8, move, "O-O-O")) {
        parsed.castle_kingside = false;
        return parsed;
    }
    else if (std.mem.eql(u8, move, "0-0-0")) {
        parsed.castle_kingside = false;
        return parsed;
    }

    parsed.class = switch (move[0]) {
        'N' => .knight,
        'B' => .bishop,
        'R' => .rook,
        'Q' => .queen,
        'K' => .king,
        'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'x' => .pawn,
        else => return null,
    };

    // skip piece char
    if (parsed.class != .pawn)
        move = move[1..];

    // disambiguation
    if (move.len >= 3 and move[1] != 'x' and (
        move[1] == 'x' or
        Coordinate.is_file(move[1]) or
        (Coordinate.is_rank(move[1]) and Coordinate.is_file(move[2]))
    )) {
        switch (move[0]) {
            'a'...'h' => parsed.source_file = Coordinate.file_from_char(move[0]),
            '1'...'8' => parsed.source_rank = Coordinate.rank_from_char(move[0]),
            else => return null,
        }
        move = move[1..];
        if (Coordinate.is_rank(move[0])) {
            if (parsed.source_rank != null)
                return null;
            parsed.source_rank = Coordinate.rank_from_char(move[0]);
            move = move[1..];
        }
    }

    if (move.len > 0 and move[0] == 'x') {
        parsed.expect_capture = true;
        move = move[1..];
    }

    if (move.len < 2) return null;
    if (!Coordinate.is_file(move[0])) return null;
    if (!Coordinate.is_rank(move[1])) return null;
    parsed.destination = Coordinate.from_string(move[0..2]);
    move = move[2..];

    // promotion
    if (move.len > 1 and move[0] == '=') {
        parsed.promote_to = switch (move[1]) {
            'N' => .knight,
            'B' => .bishop,
            'R' => .rook,
            'Q' => .queen,
            else => return null,
        };
        move = move[2..];
    }

    // valid but we don't care
    if (move.len > 0 and (move[0] == '+' or move[0] == '#'))
        move = move[1..];

    if (move.len > 0)
        return null;

    return parsed;
}
