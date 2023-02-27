// ********************************************************************************
//! https://github.com/PatrickTorgerson/hellochess
//! Copyright (c) 2022 Patrick Torgerson
//! MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const types = @import("types.zig");

const Board = @This();
const Piece = @import("Piece.zig");
const Notation = @import("Notation.zig");

const Class = Piece.Class;
const Affiliation = Piece.Affiliation;
const Square = types.Square;
const Coordinate = types.Coordinate;
const Move = types.Move;
const MoveResult = types.MoveResult;

/// the 64 squares of a chess board laid out a rank 1 to 8 file a to h
/// see Coordinate.to1d and Coordinate.from_1d for mapping
squares: [64]Square,

/// standard chess starting position
const starting_position: [64]Square = blk_starting_position: {
    var squares: [64]Square = [1]Square{Square.empty()} ** 64;
    // helper to get pieces on the back ranks
    const back_rank = struct {
        const sequence: [8]Class = blk_sequence: {
            var classes: [8]Class = undefined;
            // back rank pieces from a to h
            classes[0] = .rook;
            classes[1] = .knight;
            classes[2] = .bishop;
            classes[3] = .queen;
            classes[4] = .king;
            classes[5] = .bishop;
            classes[6] = .knight;
            classes[7] = .rook;
            break :blk_sequence classes;
        };
        /// return white piece on back rank file `file`
        pub fn white(file: u8) Square {
            return Square.init(Piece.init(sequence[file], .white));
        }
        /// return black piece on back rank file `file`
        pub fn black(file: u8) Square {
            return Square.init(Piece.init(sequence[file], .black));
        }
    };
    // iterate over files a to h (0 to 7)
    const white_pawn = Square.init(Piece.init(.pawn, .white));
    const black_pawn = Square.init(Piece.init(.pawn, .black));
    var file = 0;
    while (file < 8) : (file += 1) {
        // back rank
        squares[Coordinate.init(file, 0).to_1d()] = back_rank.white(file);
        squares[Coordinate.init(file, 7).to_1d()] = back_rank.black(file);
        // pawns
        squares[Coordinate.init(file, 1).to_1d()] = white_pawn;
        squares[Coordinate.init(file, 6).to_1d()] = black_pawn;
    }
    break :blk_starting_position squares;
};

/// create an empty board
pub fn init_empty() Board {
    return .{
        .squares = [1]Square{Square.empty()} ** 64,
    };
}

/// create a board with standard chess starting position
pub fn init() Board {
    return .{
        .squares = starting_position,
    };
}

/// return piece at coord, null if no piece
pub fn at(board: Board, pos: Coordinate) ?Piece {
    return board.squares[pos.to_1d()].piece();
}

/// submit move, move to be made pending validation
/// uses standard chess notation (https://en.wikipedia.org/wiki/Algebraic_notation_(chess))
pub fn submit_move(board: *Board, affiliation: Affiliation, move_notation: []const u8) MoveResult {
    const move = Notation.parse(move_notation) orelse return .bad_notation;

    // find a piece
    if (move.class == .pawn) {
        // push
        if (board.at(move.destination.offsetted(0, affiliation.reverse_direction()))) |piece| {
            if (!move.expect_capture and piece.eq(.pawn, affiliation)) {
                if (board.at(move.destination) != null)
                    return .blocked;
                return board.make_move(.{
                    .piece = Piece.init(.pawn, affiliation),
                    .location = move.destination.offsetted(0, affiliation.reverse_direction()),
                    .destination = move.destination,
                });
            }
        }

        // push x2 (if on starting rank)
        if (!move.expect_capture and move.destination.rank == affiliation.double_push_rank()) {
            if (board.at(move.destination.offsetted(0, affiliation.reverse_direction() * 2))) |piece| {
                if (piece.eq(.pawn, affiliation)) {
                    if (board.at(move.destination.offsetted(0, affiliation.reverse_direction())) != null)
                        return .blocked;
                    return board.make_move(.{
                        .piece = Piece.init(.pawn, affiliation),
                        .location = move.destination.offsetted(0, affiliation.reverse_direction() * 2),
                        .destination = move.destination,
                    });
                }
            }
        }

        // capture
        // TODO: en passant
        if (move.expect_capture) {
            if (move.source_file) |f| {
                if (f != move.destination.file + 1 and f != move.destination.file - 1)
                    return .no_visibility;
                if (board.at(move.destination.offsetted(f - move.destination.file, affiliation.reverse_direction()))) |piece| {
                    if (piece.eq(.pawn, affiliation)) {
                        if (board.at(move.destination)) |to_capture| {
                            if (to_capture.affiliation() == affiliation)
                                return .blocked;
                        } else return .no_visibility;
                        return board.make_move(.{
                            .piece = Piece.init(.pawn, affiliation),
                            .location = move.destination.offsetted(f - move.destination.file, affiliation.reverse_direction()),
                            .destination = move.destination,
                        });
                    } else return .bad_disambiguation;
                }
            } else {
                const left_piece = board.at(move.destination.offsetted(-1, affiliation.reverse_direction()));
                const right_piece = board.at(move.destination.offsetted(1, affiliation.reverse_direction()));

                if (left_piece == null and right_piece == null)
                    return .no_visibility;

                if (left_piece != null and right_piece != null) {
                    if (left_piece.?.neq(.pawn, affiliation) and right_piece.?.neq(.pawn, affiliation))
                        return .no_visibility;
                    if (left_piece.?.eq(.pawn, affiliation) and right_piece.?.eq(.pawn, affiliation))
                        return .ambiguous_piece;
                }

                if (left_piece) |maybe_pawn| {
                    if (maybe_pawn.eq(.pawn, affiliation)) {
                        return board.make_move(.{
                            .piece = Piece.init(.pawn, affiliation),
                            .location = move.destination.offsetted(-1, affiliation.reverse_direction()),
                            .destination = move.destination,
                        });
                    }
                }

                if (right_piece) |maybe_pawn| {
                    if (maybe_pawn.eq(.pawn, affiliation)) {
                        return board.make_move(.{
                            .piece = Piece.init(.pawn, affiliation),
                            .location = move.destination.offsetted(1, affiliation.reverse_direction()),
                            .destination = move.destination,
                        });
                    }
                }
            }
        }

        return .no_visibility; // no piece if no pawns
    }

    // TODO: back rank pieces
    return .no_visibility;
}

/// moves a pices to a different square, does no validation
pub fn make_move(board: *Board, move: Move) MoveResult {
    if (board.at(move.location)) |piece| {
        std.debug.assert(piece.bits == move.piece.bits);
        board.squares[move.location.to_1d()] = Square.empty();
        board.squares[move.destination.to_1d()] = Square.init(move.piece);
        return .ok;
    } else return .no_such_piece;
}
