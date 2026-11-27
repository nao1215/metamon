//// Finds the mutants of one Gleam module and applies them. A mutant changes
//// one operator, drops one `!`, or flips one boolean literal. The module is
//// parsed with glance, so import paths, patterns, strings and bit array
//// options are never changed.

import glance
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// One change to one module. `line` is 1-based. `text` is the trimmed source
/// line and `column` is the byte offset of the change in that trimmed line,
/// so the pair identifies a mutant even after the code moves to another line.
pub type Mutant {
  Mutant(
    file: String,
    offset: Int,
    length: Int,
    replacement: String,
    line: Int,
    text: String,
    column: Int,
    function: String,
    mutator: String,
  )
}

/// The byte offset and length of the text to replace, and what replaces it.
type Edit {
  Edit(offset: Int, length: Int, replacement: String)
}

/// Every mutant of `source`, the contents of `file`, in source order.
pub fn find(
  file file: String,
  source source: String,
) -> Result(List(Mutant), glance.Error) {
  use parsed <- result.map(glance.module(source))
  let bytes = bit_array.from_string(source)
  parsed.functions
  |> list.flat_map(fn(definition) {
    let function = definition.definition
    function.body
    |> list.flat_map(statement_edits(_, bytes))
    |> list.filter_map(to_mutant(_, file, function.name, bytes))
  })
  |> list.sort(fn(left, right) { int.compare(left.offset, right.offset) })
}

/// `source` with `mutant` applied. Fails only when the mutant was found in a
/// different source.
pub fn apply(
  source source: String,
  mutant mutant: Mutant,
) -> Result(String, Nil) {
  let bytes = bit_array.from_string(source)
  let end = mutant.offset + mutant.length
  use head <- result.try(bit_array.slice(bytes, 0, mutant.offset))
  use tail <- result.try(bit_array.slice(
    bytes,
    end,
    bit_array.byte_size(bytes) - end,
  ))
  bit_array.concat([head, bit_array.from_string(mutant.replacement), tail])
  |> bit_array.to_string
}

fn to_mutant(
  edit: Edit,
  file: String,
  function: String,
  source: BitArray,
) -> Result(Mutant, Nil) {
  use original <- result.try(slice_text(source, edit.offset, edit.length))
  use #(line, text, column) <- result.map(line_at(source, edit.offset))
  let mutator = case edit.replacement {
    "" -> "drop " <> original
    replacement -> original <> " -> " <> replacement
  }
  Mutant(
    file:,
    offset: edit.offset,
    length: edit.length,
    replacement: edit.replacement,
    line:,
    text:,
    column:,
    function:,
    mutator:,
  )
}

fn slice_text(
  source: BitArray,
  offset: Int,
  length: Int,
) -> Result(String, Nil) {
  bit_array.slice(source, offset, length)
  |> result.try(bit_array.to_string)
}

fn line_at(source: BitArray, offset: Int) -> Result(#(Int, String, Int), Nil) {
  use before <- result.try(slice_text(source, 0, offset))
  use whole <- result.try(bit_array.to_string(source))
  let lines = string.split(before, "\n")
  let number = list.length(lines)
  use start <- result.try(list.last(lines))
  use text <- result.map(
    string.split(whole, "\n") |> list.drop(number - 1) |> list.first,
  )
  #(number, string.trim(text), string.byte_size(string.trim_start(start)))
}

fn statement_edits(
  statement: glance.Statement,
  source: BitArray,
) -> List(Edit) {
  case statement {
    glance.Use(function:, ..) -> edits(function, source)
    glance.Assignment(value:, ..) -> edits(value, source)
    glance.Assert(expression:, ..) -> edits(expression, source)
    glance.Expression(expression) -> edits(expression, source)
  }
}

fn edits(expression: glance.Expression, source: BitArray) -> List(Edit) {
  case expression {
    glance.Variable(location:, name: "True") -> [
      Edit(offset: location.start, length: 4, replacement: "False"),
    ]
    glance.Variable(location:, name: "False") -> [
      Edit(offset: location.start, length: 5, replacement: "True"),
    ]
    glance.NegateBool(location:, value:) -> [
      Edit(offset: location.start, length: 1, replacement: ""),
      ..edits(value, source)
    ]
    glance.BinaryOperator(name:, left:, right:, ..) ->
      list.flatten([
        operator_edit(name, left, right, source),
        edits(left, source),
        edits(right, source),
      ])
    glance.NegateInt(value:, ..) -> edits(value, source)
    glance.Block(statements:, ..) ->
      list.flat_map(statements, statement_edits(_, source))
    glance.Fn(body:, ..) -> list.flat_map(body, statement_edits(_, source))
    glance.Tuple(elements:, ..) -> each_edits(elements, source)
    glance.List(elements:, rest:, ..) ->
      list.append(each_edits(elements, source), optional_edits(rest, source))
    glance.RecordUpdate(record:, fields:, ..) ->
      list.append(
        edits(record, source),
        list.flat_map(fields, fn(field) { optional_edits(field.item, source) }),
      )
    glance.FieldAccess(container:, ..) -> edits(container, source)
    glance.Call(function:, arguments:, ..) ->
      list.append(edits(function, source), field_edits(arguments, source))
    glance.TupleIndex(tuple:, ..) -> edits(tuple, source)
    glance.FnCapture(function:, arguments_before:, arguments_after:, ..) ->
      list.flatten([
        edits(function, source),
        field_edits(arguments_before, source),
        field_edits(arguments_after, source),
      ])
    glance.BitString(segments:, ..) ->
      list.flat_map(segments, fn(segment) { edits(segment.0, source) })
    glance.Case(subjects:, clauses:, ..) ->
      list.append(
        each_edits(subjects, source),
        list.flat_map(clauses, fn(clause) {
          list.append(
            optional_edits(clause.guard, source),
            edits(clause.body, source),
          )
        }),
      )
    glance.Int(..)
    | glance.Float(..)
    | glance.String(..)
    | glance.Variable(..)
    | glance.Panic(..)
    | glance.Todo(..)
    | glance.Echo(..) -> []
  }
}

fn each_edits(
  expressions: List(glance.Expression),
  source: BitArray,
) -> List(Edit) {
  list.flat_map(expressions, edits(_, source))
}

fn optional_edits(
  expression: Option(glance.Expression),
  source: BitArray,
) -> List(Edit) {
  case expression {
    Some(expression) -> edits(expression, source)
    None -> []
  }
}

fn field_edits(
  fields: List(glance.Field(glance.Expression)),
  source: BitArray,
) -> List(Edit) {
  list.flat_map(fields, fn(field) {
    case field {
      glance.LabelledField(item:, ..) | glance.UnlabelledField(item:) ->
        edits(item, source)
      glance.ShorthandField(..) -> []
    }
  })
}

/// The replacements, in the style of gremlins and Stryker. Pipes and string
/// concatenation are left alone.
fn replacement(operator: glance.BinaryOperator) -> Option(#(String, String)) {
  case operator {
    glance.And -> Some(#("&&", "||"))
    glance.Or -> Some(#("||", "&&"))
    glance.Eq -> Some(#("==", "!="))
    glance.NotEq -> Some(#("!=", "=="))
    glance.LtInt -> Some(#("<", "<="))
    glance.LtEqInt -> Some(#("<=", "<"))
    glance.GtInt -> Some(#(">", ">="))
    glance.GtEqInt -> Some(#(">=", ">"))
    glance.LtFloat -> Some(#("<.", "<=."))
    glance.LtEqFloat -> Some(#("<=.", "<."))
    glance.GtFloat -> Some(#(">.", ">=."))
    glance.GtEqFloat -> Some(#(">=.", ">."))
    glance.AddInt -> Some(#("+", "-"))
    glance.SubInt -> Some(#("-", "+"))
    glance.MultInt -> Some(#("*", "/"))
    glance.DivInt -> Some(#("/", "*"))
    glance.RemainderInt -> Some(#("%", "*"))
    glance.AddFloat -> Some(#("+.", "-."))
    glance.SubFloat -> Some(#("-.", "+."))
    glance.MultFloat -> Some(#("*.", "/."))
    glance.DivFloat -> Some(#("/.", "*."))
    glance.Pipe | glance.Concatenate -> None
  }
}

/// glance records where the operands are, not the operator, so the operator
/// is the first occurrence of its text between them outside a comment.
fn operator_edit(
  operator: glance.BinaryOperator,
  left: glance.Expression,
  right: glance.Expression,
  source: BitArray,
) -> List(Edit) {
  let start = location(left).end
  let found = {
    use #(text, with) <- result.try(option.to_result(replacement(operator), Nil))
    use gap <- result.try(slice_text(
      source,
      start,
      location(right).start - start,
    ))
    use at <- result.map(find_operator(gap, text, 0))
    Edit(offset: start + at, length: string.byte_size(text), replacement: with)
  }
  case found {
    Ok(edit) -> [edit]
    Error(Nil) -> []
  }
}

fn find_operator(gap: String, text: String, at: Int) -> Result(Int, Nil) {
  case gap {
    "" -> Error(Nil)
    "//" <> _ -> {
      use #(comment, rest) <- result.try(string.split_once(gap, "\n"))
      find_operator(rest, text, at + string.byte_size(comment) + 1)
    }
    _ ->
      case string.starts_with(gap, text) {
        True -> Ok(at)
        False -> {
          use #(first, rest) <- result.try(string.pop_grapheme(gap))
          find_operator(rest, text, at + string.byte_size(first))
        }
      }
  }
}

fn location(expression: glance.Expression) -> glance.Span {
  case expression {
    glance.Int(location:, ..)
    | glance.Float(location:, ..)
    | glance.String(location:, ..)
    | glance.Variable(location:, ..)
    | glance.NegateInt(location:, ..)
    | glance.NegateBool(location:, ..)
    | glance.Block(location:, ..)
    | glance.Panic(location:, ..)
    | glance.Todo(location:, ..)
    | glance.Tuple(location:, ..)
    | glance.List(location:, ..)
    | glance.Fn(location:, ..)
    | glance.RecordUpdate(location:, ..)
    | glance.FieldAccess(location:, ..)
    | glance.Call(location:, ..)
    | glance.TupleIndex(location:, ..)
    | glance.FnCapture(location:, ..)
    | glance.BitString(location:, ..)
    | glance.Case(location:, ..)
    | glance.BinaryOperator(location:, ..)
    | glance.Echo(location:, ..) -> location
  }
}
