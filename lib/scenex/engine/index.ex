defmodule Scenex.Engine.Index do
  @moduledoc """
  Parser and evaluator for the **Overall Index formula** — the single derived
  headline metric a scenario rolls its values up into (an author might label it
  "Democracy", "Ship Integrity", "The Realm's Fate"…).

  Unlike a value's aggregation formula (`Scenex.Engine.Formula`, which folds one
  value's *per-group* numbers into that value's global), the index combines the
  **globals of different values, each referenced by its key**:

    * a value key — a bare lowercase slug (`stability`, `resources`), resolved to
      that value's current global
    * numeric literals
    * the operators `+ - * /` with the usual precedence
    * parentheses and unary minus

  Examples: `"stability"`, `"2*stability + 3*resources"`, `"(stability + risk) / 2"`.

  References are **raw**: a value's global enters at its own scale, so an author
  combining values on different scales normalises explicitly in the formula
  (e.g. `stability/10 + resources/100`). This is deliberate — one-time authoring
  work in exchange for full control.

  Pure and self-contained — no Ecto, no processes. Powers the dry-run sandbox
  and live sessions alike.

  ## Examples

      iex> Scenex.Engine.Index.evaluate("2*stability + resources", %{"stability" => 3, "resources" => 4})
      {:ok, 10}

      iex> Scenex.Engine.Index.evaluate("(stability + risk) / 2", %{"stability" => 6, "risk" => 2})
      {:ok, 4.0}

      iex> Scenex.Engine.Index.validate("2 * ")
      {:error, :unexpected_end}

      iex> Scenex.Engine.Index.validate("stability + trust", keys: ["stability", "resources"])
      {:error, {:unknown_value_key, "trust"}}
  """

  @type ast ::
          {:num, number()}
          | {:ref, String.t()}
          | {:neg, ast()}
          | {:binop, :plus | :minus | :times | :divide, ast(), ast()}

  @typedoc "Evaluation context: current global value per value key (string)."
  @type context :: %{optional(String.t()) => number()}

  @doc "Parse a formula string into an AST."
  @spec parse(String.t()) :: {:ok, ast()} | {:error, term()}
  def parse(formula) when is_binary(formula) do
    with {:ok, tokens} <- tokenize(formula) do
      try do
        {ast, rest} = parse_expr(tokens)
        if rest == [], do: {:ok, ast}, else: {:error, {:unexpected_token, hd(rest)}}
      catch
        {:parse_error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Validate a formula's syntax and, optionally, its value references.

    * `:keys` — a list of known value keys; if given, a reference to any other
      key is rejected with `{:error, {:unknown_value_key, key}}`.
  """
  @spec validate(String.t(), keyword()) :: :ok | {:error, term()}
  def validate(formula, opts \\ []) when is_binary(formula) do
    with {:ok, ast} <- parse(formula) do
      check_keys(references(ast), Keyword.get(opts, :keys))
    end
  end

  @doc """
  Evaluate a formula (string or pre-parsed AST) against a `context`.

  Returns `{:error, {:unknown_value, key}}` when the formula references a value
  absent from the context, and `{:error, :division_by_zero}` on division by zero.
  """
  @spec evaluate(String.t() | ast(), context()) :: {:ok, number()} | {:error, term()}
  def evaluate(formula, context) when is_binary(formula) and is_map(context) do
    with {:ok, ast} <- parse(formula), do: eval(ast, context)
  end

  def evaluate(ast, context) when is_tuple(ast) and is_map(context), do: eval(ast, context)

  @doc "All value keys the formula references."
  @spec references(String.t() | ast()) :: [String.t()] | {:error, term()}
  def references(formula) when is_binary(formula) do
    with {:ok, ast} <- parse(formula), do: references(ast)
  end

  def references(ast) when is_tuple(ast), do: Enum.uniq(collect_refs(ast))

  # --- validation helpers ---

  defp check_keys(_refs, nil), do: :ok

  defp check_keys(refs, keys) when is_list(keys) do
    case Enum.find(refs, &(&1 not in keys)) do
      nil -> :ok
      key -> {:error, {:unknown_value_key, key}}
    end
  end

  defp collect_refs({:num, _n}), do: []
  defp collect_refs({:ref, key}), do: [key]
  defp collect_refs({:neg, node}), do: collect_refs(node)
  defp collect_refs({:binop, _op, left, right}), do: collect_refs(left) ++ collect_refs(right)

  # --- evaluation ---

  defp eval({:num, n}, _context), do: {:ok, n}

  defp eval({:ref, key}, context) do
    case Map.fetch(context, key) do
      {:ok, number} when is_number(number) -> {:ok, number}
      {:ok, _other} -> {:error, {:unknown_value, key}}
      :error -> {:error, {:unknown_value, key}}
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

  defp apply_op(:plus, a, b), do: {:ok, a + b}
  defp apply_op(:minus, a, b), do: {:ok, a - b}
  defp apply_op(:times, a, b), do: {:ok, a * b}
  defp apply_op(:divide, _a, b) when b == 0, do: {:error, :division_by_zero}
  defp apply_op(:divide, a, b), do: {:ok, a / b}

  # --- recursive-descent parser ---
  # expr   := term (("+" | "-") term)*
  # term   := factor (("*" | "/") factor)*
  # factor := number | ref | "(" expr ")" | "-" factor

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
  defp parse_factor([{:ref, key} | rest]), do: {{:ref, key}, rest}

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
      Regex.scan(~r/\d+\.\d+|\d+|[a-z][a-z0-9_]*|[()+\-*\/]/, input)
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
    if Regex.match?(~r/^\d/, token),
      do: {:num, parse_number(token)},
      else: {:ref, token}
  end

  defp parse_number(token) do
    if String.contains?(token, "."),
      do: String.to_float(token),
      else: String.to_integer(token)
  end
end
