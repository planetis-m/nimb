import std/strutils

import nimb/db

type
  SqlFragment* = object
    sql*: string
    params*: seq[DbValue]

  RenderedQuery* = object
    sql*: string
    params*: seq[DbValue]

proc quoteIdentifierPart(part: string): string =
  if part == "*":
    return part
  result = "\""
  for ch in part:
    if ch == '"':
      result.add("\"\"")
    else:
      result.add(ch)
  result.add('"')

proc quoteIdent*(name: string): string =
  let parts = name.split('.')
  for index, part in parts:
    if index > 0:
      result.add('.')
    result.add(quoteIdentifierPart(part))

proc raw*(sql: string; params: varargs[DbValue, `!?`]): SqlFragment =
  SqlFragment(sql: sql, params: @params)

proc ident*(name: string): SqlFragment =
  SqlFragment(sql: quoteIdent(name), params: @[])

proc alias*(fragment: SqlFragment; name: string): SqlFragment =
  SqlFragment(sql: fragment.sql & " AS " & quoteIdent(name),
    params: fragment.params)

proc render*(fragment: SqlFragment): RenderedQuery =
  RenderedQuery(sql: fragment.sql, params: fragment.params)
