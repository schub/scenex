defmodule Scenex.Engine.Condition do
  @moduledoc """
  Parser and evaluator for **conditions** (gates and ending recommendations).

  A condition is a single comparison between two arithmetic expressions over
  value references:

    * `self(key)` — the deciding group's current value (event options only)
    * `global(key)` — the derived global value
    * numeric literals, `+ - * /`, parentheses, unary minus
    * exactly one comparator: `>=  <=  >  <  ==  !=`

  Examples: `"self(resources) >= 3"`, `"global(risk) < 8"`,
  `"(self(stability) + self(solidarity)) / 2 > 5"`.

  Boolean combinations (`and` / `or`) are deliberately deferred.

  Pure and self-contained — no Ecto, no processes. The same evaluator powers
  option gates, ending recommendations, and (later) GM hints.

  ## Examples

      iex> Scenex.Engine.Condition.evaluate("self(resources) >= 3", %{self: %{"resources" => 5}})
      {:ok, true}

      iex> Scenex.Engine.Condition.evaluate("global(risk) < 8", %{global: %{"risk" => 8.5}})
      {:ok, false}

      iex> Scenex.Engine.Condition.validate("global(risk)")
      {:error, :missing_comparison}

      iex> Scenex.Engine.Condition.validate("self(risk) > 1 > 2")
      {:error, :multiple_comparisons}

      iex> Scenex.Engine.Condition.validate("self(resources) >= 3", allow_self: false)
      {:error, :self_not_allowed}
  """

  @type scope :: :self | :global
  @type expr ::
          {:num, number()}
          | {:ref, scope(), String.t()}
          | {:neg, expr()}
          | {:binop, :plus | :minus | :times | :divide, expr(), expr()}
  @type comparator :: :gte | :lte | :gt | :lt | :eq | :neq
  @type ast :: {:cmp, comparator(), expr(), expr()}

  @typedoc """
  Evaluation context: current values by scope, keyed by value key (string).
  A scope may be omitted (e.g. no `:self` when evaluating an ending).
  """
  @type context :: %{
          optional(:self) => %{String.t() => number()},
          optional(:global) => %{String.t() => number()}
        }

  @comparators %{">=" => :gte, "<=" => :lte, ">" => :gt, "<" => :lt, "==" => :eq, "!=" => :neq}
  @scopes %{"self" => :self, "global" => :global}

  @doc "Parse a condition string into an AST."
  @spec parse(String.t()) :: {:ok, ast()} | {:error, term()}
  def parse(condition) when is_binary(condition) do
    with {:ok, tokens} <- tokenize(condition) do
      try do
        {left, rest} = parse_expr(tokens)

        case rest do
          [{:cmp, op} | rest2] ->
            {right, rest3} = parse_expr(rest2)

            case rest3 do
              [] -> {:ok, {:cmp, op, left, right}}
              [{:cmp, _} | _] -> {:error, :multiple_comparisons}
              [token | _] -> {:error, {:unexpected_token, token}}
            end

          [] ->
            {:error, :missing_comparison}

          [token | _] ->
            {:error, {:unexpected_token, token}}
        end
      catch
        {:parse_error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Validate a condition's syntax and references. Returns `:ok` or `{:error, reason}`.

  Options:

    * `:allow_self` — whether `self(...)` references are permitted (default
      `true`; pass `false` for election options and endings, where no single
      group decides).
    * `:keys` — a list of known value keys; if given, references to other keys
      are rejected with `{:error, {:unknown_value_key, key}}`.
  """
  @spec validate(String.t(), keyword()) :: :ok | {:error, term()}
  def validate(condition, opts \\ []) when is_binary(condition) do
    with {:ok, ast} <- parse(condition) do
      refs = references(ast)

      with :ok <- check_self(refs, Keyword.get(opts, :allow_self, true)) do
        check_keys(refs, Keyword.get(opts, :keys))
      end
    end
  end

  @doc """
  Evaluate a condition (string or pre-parsed AST) against a context.

  Returns `{:ok, boolean}`, or `{:error, reason}` when a referenced scope is
  absent from the context, a key is unknown, or a division by zero occurs.
  """
  @spec evaluate(String.t() | ast(), context()) :: {:ok, boolean()} | {:error, term()}
  def evaluate(condition, context) when is_binary(condition) do
    with {:ok, ast} <- parse(condition), do: evaluate(ast, context)
  end

  def evaluate({:cmp, op, left, right}, context) when is_map(context) do
    with {:ok, lv} <- eval(left, context),
         {:ok, rv} <- eval(right, context) do
      {:ok, compare(op, lv, rv)}
    end
  end

  @doc "All value references in a condition, as `{scope, key}` tuples."
  @spec references(String.t() | ast()) :: [{scope(), String.t()}] | {:error, term()}
  def references(condition) when is_binary(condition) do
    with {:ok, ast} <- parse(condition), do: references(ast)
  end

  def references({:cmp, _op, left, right}),
    do: Enum.uniq(collect_refs(left) ++ collect_refs(right))

  # --- validation helpers ---

  defp check_self(_refs, true), do: :ok

  defp check_self(refs, false) do
    if Enum.any?(refs, fn {scope, _key} -> scope == :self end),
      do: {:error, :self_not_allowed},
      else: :ok
  end

  defp check_keys(_refs, nil), do: :ok

  defp check_keys(refs, keys) when is_list(keys) do
    case Enum.find(refs, fn {_scope, key} -> key not in keys end) do
      nil -> :ok
      {_scope, key} -> {:error, {:unknown_value_key, key}}
    end
  end

  defp collect_refs({:num, _n}), do: []
  defp collect_refs({:ref, scope, key}), do: [{scope, key}]
  defp collect_refs({:neg, node}), do: collect_refs(node)
  defp collect_refs({:binop, _op, left, right}), do: collect_refs(left) ++ collect_refs(right)

  # --- evaluation ---

  defp eval({:num, n}, _context), do: {:ok, n}

  defp eval({:ref, scope, key}, context) do
    case context do
      %{^scope => values} when is_map(values) -> fetch_value(values, scope, key)
      _ -> {:error, {:scope_unavailable, scope}}
    end
  end

  defp eval({:neg, node}, context) do
    with {:ok, v} <- eval(node, context), do: {:ok, -v}
  end

  defp eval({:binop, op, left, right}, context) do
    with {:ok, lv} <- eval(left, context),
         {:ok, rv} <- eval(right, context) do
      apply_op(op, lv, rv)
    end
  end

  defp fetch_value(values, scope, key) do
    case Map.fetch(values, key) do
      {:ok, number} when is_number(number) -> {:ok, number}
      {:ok, _other} -> {:error, {:no_value, scope, key}}
      :error -> {:error, {:unknown_value, scope, key}}
    end
  end

  defp apply_op(:plus, a, b), do: {:ok, a + b}
  defp apply_op(:minus, a, b), do: {:ok, a - b}
  defp apply_op(:times, a, b), do: {:ok, a * b}
  defp apply_op(:divide, _a, b) when b == 0, do: {:error, :division_by_zero}
  defp apply_op(:divide, a, b), do: {:ok, a / b}

  defp compare(:gte, a, b), do: a >= b
  defp compare(:lte, a, b), do: a <= b
  defp compare(:gt, a, b), do: a > b
  defp compare(:lt, a, b), do: a < b
  defp compare(:eq, a, b), do: a == b
  defp compare(:neq, a, b), do: a != b

  # --- recursive-descent parser ---
  # condition := expr cmp expr
  # expr      := term (("+" | "-") term)*
  # term      := factor (("*" | "/") factor)*
  # factor    := number | ref | "(" expr ")" | "-" factor
  # ref       := ("self" | "global") "(" identifier ")"

  defp parse_expr(tokens) do
    {left, rest} = parse_term(tokens)
    parse_add(left, rest)
  end

  defp parse_add(left, [{:op, op} | rest]) when op in [:plus, :minus] do
    {right, rest2} = parse_term(rest)
    parse_add({:binop, op, left, right}, rest2)
  end

  defp parse_add(left, rest), do: {left, rest}

  defp parse_term(tokens) do
    {left, rest} = parse_factor(tokens)
    parse_mul(left, rest)
  end

  defp parse_mul(left, [{:op, op} | rest]) when op in [:times, :divide] do
    {right, rest2} = parse_factor(rest)
    parse_mul({:binop, op, left, right}, rest2)
  end

  defp parse_mul(left, rest), do: {left, rest}

  defp parse_factor([{:num, n} | rest]), do: {{:num, n}, rest}

  defp parse_factor([{:scope, scope} | rest]) do
    case rest do
      [:lparen, {:ident, key}, :rparen | rest2] -> {{:ref, scope, key}, rest2}
      _ -> throw({:parse_error, {:invalid_reference, to_string(scope)}})
    end
  end

  defp parse_factor([{:ident, name} | _rest]),
    do: throw({:parse_error, {:unknown_reference, name}})

  defp parse_factor([{:op, :minus} | rest]) do
    {factor, rest2} = parse_factor(rest)
    {{:neg, factor}, rest2}
  end

  defp parse_factor([:lparen | rest]) do
    {ast, rest2} = parse_expr(rest)

    case rest2 do
      [:rparen | rest3] -> {ast, rest3}
      _ -> throw({:parse_error, :missing_closing_paren})
    end
  end

  defp parse_factor([]), do: throw({:parse_error, :unexpected_end})
  defp parse_factor([token | _]), do: throw({:parse_error, {:unexpected_token, token}})

  # --- tokenizer ---

  defp tokenize(input) do
    raw =
      Regex.scan(~r/\d+\.\d+|\d+|[a-zA-Z_][a-zA-Z0-9_]*|>=|<=|==|!=|[><()+\-*\/]/, input)
      |> List.flatten()

    stripped = String.replace(input, ~r/\s/, "")

    if stripped != "" and Enum.join(raw) == stripped do
      {:ok, Enum.map(raw, &classify/1)}
    else
      {:error, :invalid_syntax}
    end
  end

  defp classify("("), do: :lparen
  defp classify(")"), do: :rparen
  defp classify("+"), do: {:op, :plus}
  defp classify("-"), do: {:op, :minus}
  defp classify("*"), do: {:op, :times}
  defp classify("/"), do: {:op, :divide}

  defp classify(token) do
    cond do
      Map.has_key?(@comparators, token) -> {:cmp, @comparators[token]}
      Regex.match?(~r/^\d/, token) -> {:num, parse_number(token)}
      Map.has_key?(@scopes, token) -> {:scope, @scopes[token]}
      true -> {:ident, token}
    end
  end

  defp parse_number(token) do
    if String.contains?(token, "."),
      do: String.to_float(token),
      else: String.to_integer(token)
  end
end
