provide *

import file("visitors/ast-transformer.arr") as AT
import ast-visitors as AV
import ast as A
import parse-pyret as SP
import file as F
include either
import string-dict as D

dummy = A.dummy-loc

fun generate-ast-visitor(
    imports :: List<A.Import>,
    in-file :: String,
    out-file :: String,
    requirements :: List<String>,
    is-strip-annotation :: Boolean,
    transformer :: (List<AT.SimplifiedVariant>, List<A.Expr> -> List<A.Expr>)):

  p = AT.read(in-file)
  {collected-variants; collected-data-definitions} = AT.collect-ast(p)
  shadow get-arg-type = AT.get-arg-type(_, collected-data-definitions)

  fun default-map-visitor-transform(variant :: AT.SimplifiedVariant) -> A.Expr:
    cases (AT.SimplifiedVariant) variant:
      | simplified-variant(_, name, members) =>
        member-args = members.map(lam(b :: A.Bind) -> A.Expr:
          id = AT.bind-to-id(b)
          # assume that arg-list and arg-option is one level deep
          arg-type = get-arg-type(b.ann)
          if arg-type.is-visitable():
            cases (AT.VisitableArgType) arg-type:
              | arg-visitable => AT.make-visit-self(id)
              | arg-list(_) => AT.make-complex-visit(id, "list")
              | arg-option(_) => AT.make-complex-visit(id, "option")
            end
          else:
            id
          end
        end)
        A.s-app(dummy, AT.make-id(name), member-args)
      | simplified-singleton-variant(_, name, _) => AT.make-id(name)
    end
  end

  fun default-iter-visitor-transform(variant :: AT.SimplifiedVariant) -> A.Expr:
    cases (AT.SimplifiedVariant) variant:
      | simplified-variant(_, name, members) =>
        member-args = for lists.filter-map(b from members):
          # assume that arg-list and arg-option is one level deep
          id = AT.bind-to-id(b)
          arg-type = get-arg-type(b.ann)
          if arg-type.is-visitable():
            cases (AT.VisitableArgType) arg-type:
              | arg-visitable => some(AT.make-visit-self(id))
              | arg-list(_) => some(AT.make-complex-visit(id, "list"))
              | arg-option(_) => some(AT.make-complex-visit(id, "option"))
            end
          else:
            none
          end
        end
        cases (List) member-args:
          | empty => A.s-bool(dummy, true)
          | link(f, r) =>
            # left recursion
            for fold(prev from f, e from r):
              A.s-op(dummy, dummy, "opand", prev, e)
            end
        end
      | simplified-singleton-variant(_, name, _) => A.s-bool(dummy, true)
    end
  end

  fun dummy-loc-visitor-transform(variant :: AT.SimplifiedVariant) -> A.Expr:
    cases (AT.SimplifiedVariant) variant:
      | simplified-variant(_, name, members) =>
        member-args = members.map(lam(b :: A.Bind) -> A.Expr:
          # assume that arg-list and arg-option is one level deep
          id = AT.bind-to-id(b)
          arg-type = get-arg-type(b.ann)
          if arg-type.is-visitable():
            cases (AT.VisitableArgType) arg-type:
              | arg-visitable => AT.make-visit-self(id)
              | arg-list(_) => AT.make-complex-visit(id, "list")
              | arg-option(_) => AT.make-complex-visit(id, "option")
            end
          else:
            id
          end
        end)
        shadow member-args = for map2(bind from members, arg from member-args):
          # assume bind is a `s-bind`
          if AT.is-loc(bind.ann):
            AT.make-id("dummy-loc")
          else:
            arg
          end
        end
        shadow member-args = ask:
          | name == 's-lam' then: member-args.set(1, A.s-str(dummy, ''))
          | otherwise: member-args
        end
        A.s-app(dummy, AT.make-id(name), member-args)
      | simplified-singleton-variant(_, name, _) => AT.make-id(name)
    end
  end

  fun ast-to-term-visitor-transform(variant :: AT.SimplifiedVariant) -> A.Expr:
    cases (AT.SimplifiedVariant) variant block:
      | simplified-variant(type-name, name, members) =>
        args = for map(b from members):
          # assume b is s-bind
          id = AT.bind-to-id(b)
          arg-type = get-arg-type(b.ann)
          if arg-type.is-visitable():
            cases (AT.VisitableArgType) arg-type:
              | arg-visitable => AT.make-visit-self(id)
              | arg-list(_) => AT.make-node-1("g-list", AT.make-complex-visit(id, "list"))
              | arg-option(_) => AT.make-node-1("g-option", AT.make-complex-visit(id, "option"))
            end
          else:
            fun make-node-complex(
              tag :: String,
              meth :: String,
              inner :: AT.Tag
            ) -> A.Expr:
              # assume inner is one level deep
              shadow inner = cases (AT.Tag) inner:
                | t-str => "g-str"
                | t-num => "g-num"
                | t-bool => "g-bool"
                | t-loc => "g-loc"
              end
              AT.make-node-1(
                tag,
                AT.make-method-call(id, meth, [list: AT.make-id(inner)]))
            end
            cases (AT.Tag) AT.get-tag(b.ann):
              | t-str => AT.make-node-1("g-str", id)
              | t-num => AT.make-node-1("g-num", id)
              | t-bool => AT.make-node-1("g-bool", id)
              | t-loc => AT.make-node-1("g-loc", id)
              | t-list(inner) => make-node-complex("g-list", "map", inner)
              | t-option(inner) => make-node-complex("g-option", "and-then", inner)
            end
          end
        end
        {opt-loc; shadow args} = cases (List) members:
          | empty => {AT.make-name("none"); args}
          | link(first, rest) =>
            cases (AT.Tag) AT.get-tag(first.ann):
              | t-loc =>
                {AT.make-node-1("some", AT.bind-to-id(first)); args.drop(1)}
              | else =>
                {AT.make-name("none"); args}
            end
        end
        A.s-app(dummy, AT.make-id("g-surf"), [list: A.s-str(dummy, name), opt-loc, AT.make-list(args)])
      | simplified-singleton-variant(_, name, _) =>
        A.s-app(dummy, AT.make-id("g-surf"), [list: A.s-str(dummy, name), AT.make-name("none"), AT.make-list(empty)])
    end
  end

  transformers = [D.string-dict:
    'default-map-visitor', {
      transformer: default-map-visitor-transform,
      preamble: ```{
        method option(self, opt):
          cases(Option) opt:
            | none => none
            | some(v) => some(v.visit(self))
          end
        end,
        method list(self, lst):
          cases(List) lst:
            | empty => empty
            | link(f, r) => link(f.visit(self), self.list(r))
          end
        end,
      }```
    },
    'default-iter-visitor', {
      transformer: default-iter-visitor-transform,
      preamble: ```{
        method option(self, opt):
          cases(Option) opt:
            | none => true
            | some(v) => v.visit(self)
          end
        end,
        method list(self, lst):
          cases(List) lst:
            | empty => true
            | link(f, r) => f.visit(self) and self.list(r)
          end
        end,
      }```
    },
    'dummy-loc-visitor', {
      transformer: dummy-loc-visitor-transform,
      preamble: ```{
        method option(self, opt):
          cases(Option) opt:
            | none => none
            | some(v) => some(v.visit(self))
          end
        end,
        method list(self, lst):
          cases(List) lst:
            | empty => empty
            | link(f, r) => link(f.visit(self), self.list(r))
          end
        end,
      }```
    },
    'ast-to-term-visitor', {
      transformer: ast-to-term-visitor-transform,
      preamble: ```{
        method option(self, opt):
          cases(Option) opt:
            | none => none
            | some(v) => some(v.visit(self))
          end
        end,
        method list(self, lst):
          cases(List) lst:
            | empty => empty
            | link(f, r) => link(f.visit(self), self.list(r))
          end
        end,
      }```
    }
  ]

  body = for map(vname from requirements):
    obj = transformers.get-value(vname)
    AT.visitor-maker(
      collected-variants,
      vname,
      obj.transformer,
      is-strip-annotation,
      obj.preamble)
  end

  out-program =
    A.s-program(dummy,
      A.s-provide-all(dummy),
      A.s-provide-types-none(dummy),
      imports + [list:
        A.s-import(dummy, A.s-const-import(dummy, "global"), A.s-underscore(dummy)),
        A.s-import(dummy, A.s-const-import(dummy, "base"), A.s-underscore(dummy))],
      A.s-block(dummy, transformer(collected-variants, body)))

  as-string = '# THIS FILE IS AUTOMATICALLY GENERATED FROM autogenerate.arr. PLEASE DO NOT EDIT.\n' + out-program.tosource().pretty(80).join-str("\n")

  F.output-file(out-file, false).display(as-string)
end


fun write-ast-visitors() block:
  generate-ast-visitor(
    [list:
      A.s-include(dummy, A.s-const-import(dummy, 'ast')),
      A.s-include(dummy, A.s-const-import(dummy, 'lists')),
      A.s-include(dummy, A.s-const-import(dummy, 'option'))],
    'src/arr/trove/ast.arr',
    'src/arr/trove/ast-visitors.arr',
    [list: 'default-map-visitor', 'default-iter-visitor', 'dummy-loc-visitor'],
    true,
    lam(_, body): body end)


  generate-ast-visitor(
    [list:
      A.s-include(dummy, A.s-const-import(dummy, 'ast')),
      A.s-include(dummy, A.s-const-import(dummy, 'string-dict')),
      A.s-include(dummy, A.s-special-import(dummy, 'file', [list: 'ds-structs.arr'])),
    ],
    'src/arr/trove/ast.arr',
    'src/arr/desugar/conversion-visitor.arr',
    [list: 'ast-to-term-visitor'],
    true,
    lam(collected-variants :: List<AT.SimplifiedVariant>, body) -> List<A.Expr> block:
      fun get-arg-list(lst :: List<A.Bind>) -> List<A.Expr>:
        for map_n(i from 0, _ from lst):
          [list: AT.make-method-call(AT.make-id('args'), 'get', [list: A.s-num(dummy, i)])]
            ^ A.s-app(dummy, AT.make-id("term-to-ast"), _)
        end
      end

      # use string-dict so that we can simply lookup without searching
      # (searching strategy's performance is really bad!)
      var string-dict-args = empty

      for each(variant from collected-variants) block:
        bodylam = cases (AT.SimplifiedVariant) variant:
          | simplified-variant(_, name, members) =>
            arg-list = cases (List) members:
              | empty => empty
              | link(first, rest) =>
                cases (AT.Tag) AT.get-tag(first.ann):
                  | t-loc =>
                    link(A.s-dot(dummy, AT.make-id('maybe-loc'), 'value'), get-arg-list(rest))
                  | else => get-arg-list(members)
                end
            end
            A.s-app(dummy, AT.make-id(name),arg-list)
          | simplified-singleton-variant(_, name, _) => AT.make-id(name)
        end

        string-dict-args := link(A.s-str(dummy, variant.name), string-dict-args)
        string-dict-args := link(
          A.s-lam(
            dummy, "", empty, [list: "maybe-loc", "args"].map(AT.make-bind),
            A.a-blank, "", bodylam, none, none, false),
          string-dict-args)
      end

      lookup-dict = A.s-construct(
        dummy,
        A.s-construct-normal,
        AT.make-id("string-dict"),
        string-dict-args.reverse())

      degeneric-str = ```

      rec lookup-dict = ...

      fun term-to-ast(g):
        cases (Term) g:
          | g-surf(op, maybe-loc, args) => lookup-dict.get-value(op)(maybe-loc, args)
          | g-core(op, maybe-loc, args) => lookup-dict.get-value(op)(maybe-loc, args)
          | g-aux(_, _, _) => raise("unexpected g-aux: " + tostring(g))
          | g-value(val) =>
            cases (GenericPrimitive) val:
              | e-str(s) => s
              | e-num(n) => n
              | e-bool(b) => b
              | e-loc(l) => l
            end
          | g-var(v) =>
            ask block:
              | v.global and (v.kind == some(type-var)) then: s-type-global(v.name)
              | v.global and (v.kind == some(value-var)) then: s-global(v.name)
              | v.global then:
                print("warning: global variable coerced to a value: " + tostring(v))
                s-global(v.name)
              | v.serial <> 0 then: s-atom(v.name, v.serial)
              | otherwise: s-name(v.loc, v.name) # TODO: s-underscore
            end
          | g-list(lst) => lst.map(term-to-ast)
          | g-option(opt) => opt.and-then(term-to-ast)
          | g-tag(_, _, body) => term-to-ast(body)
        end
      end
      ```

      helpers-str = ```
        fun g-str(s): g-value(e-str(s)) end
        fun g-num(s): g-value(e-num(s)) end
        fun g-bool(s): g-value(e-bool(s)) end
        fun g-loc(s): g-value(e-loc(s)) end
        ```

      degeneric = SP.surface-parse(degeneric-str, '').visit(AV.default-map-visitor.{
        method s-template(self, _):
          lookup-dict
        end
      })

      helpers = SP.surface-parse(helpers-str, '')
      helpers.block.stmts + body + degeneric.block.stmts
    end)
end