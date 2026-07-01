defmodule Scenex.Engine.Formula do
  @moduledoc """
  Parser and evaluator for **aggregation formulas**.

  A global value is derived from the per-group values of a `ValueDefinition` by
  an aggregation formula — a small expression language:

    * aggregations over the list of group values: `min`, `max`, `avg`
      (alias `average`), `median`, `sum`
    * numeric literals
    * the operators `+ - * /` with the usual precedence
    * parentheses and unary minus

  Examples: `"avg"`, `"max"`, `"(avg + min) / 2"`, `"sum / 2"`.

  Pure and self-contained — no Ecto, no processes. Used by the simulation core
  (Phase 2 simulate mode and Phase 3 live sessions alike).

  ## Examples

      iex> Scenex.Engine.Formula.evaluate("avg", [10, 20, 30])
      {:ok, 20.0}

      iex> Scenex.Engine.Formula.evaluate("(avg + min) / 2", [10, 20, 30])
      {:ok, 15.0}

      iex> Scenex.Engine.Formula.validate("(avg + min")
      {:error, :missing_closing_paren}
  """

  @type ast ::
          {:num, number()}
          | {:agg, :min | :max | :avg | :median | :sum}
          | {:neg, ast()}
          | {:binop, :plus | :minus | :times | :divide, ast(), ast()}

  @aggregations %{
    "min" => :min,
    "max" => :max,
    "avg" => :avg,
    "average" => :avg,
    "median" => :median,
    "sum" => :sum
  }

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

  @doc "Validate a formula's syntax. Returns `:ok` or `{:error, reason}`."
  @spec validate(String.t()) :: :ok | {:error, term()}
  def validate(formula) when is_binary(formula) do
    case parse(formula) do
      {:ok, _ast} -> :ok
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Evaluate a formula (string or pre-parsed AST) against a list of group values.

  Returns `{:error, :empty}` if an aggregation is evaluated over an empty list,
  and `{:error, :division_by_zero}` on division by zero.
  """
  @spec evaluate(String.t() | ast(), [number()]) :: {:ok, number()} | {:error, term()}
  def evaluate(formula, values) when is_binary(formula) do
    with {:ok, ast} <- parse(formula), do: eval(ast, values)
  end

  def evaluate(ast, values) when is_tuple(ast), do: eval(ast, values)

  # --- evaluation ---

  defp eval({:num, n}, _values), do: {:ok, n}
  defp eval({:agg, agg}, values), do: aggregate(agg, values)

  defp eval({:neg, node}, values) do
    with {:ok, v} <- eval(node, values), do: {:ok, -v}
  end

  defp eval({:binop, op, left, right}, values) do
    with {:ok, lv} <- eval(left, values),
         {:ok, rv} <- eval(right, values) do
      apply_op(op, lv, rv)
    end
  end

  defp apply_op(:plus, a, b), do: {:ok, a + b}
  defp apply_op(:minus, a, b), do: {:ok, a - b}
  defp apply_op(:times, a, b), do: {:ok, a * b}
  defp apply_op(:divide, _a, b) when b == 0, do: {:error, :division_by_zero}
  defp apply_op(:divide, a, b), do: {:ok, a / b}

  defp aggregate(_agg, []), do: {:error, :empty}
  defp aggregate(:min, values), do: {:ok, Enum.min(values)}
  defp aggregate(:max, values), do: {:ok, Enum.max(values)}
  defp aggregate(:sum, values), do: {:ok, Enum.sum(values)}
  defp aggregate(:avg, values), do: {:ok, Enum.sum(values) / length(values)}
  defp aggregate(:median, values), do: {:ok, median(values)}

  defp median(values) do
    sorted = Enum.sort(values)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 1 do
      Enum.at(sorted, mid)
    else
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    end
  end

  # --- recursive-descent parser ---
  # expr := term (("+" | "-") term)*
  # term := factor (("*" | "/") factor)*
  # factor := number | aggregation | "(" expr ")" | "-" factor

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
  defp parse_factor([{:agg, agg} | rest]), do: {{:agg, agg}, rest}

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
    raw = Regex.scan(~r/\d+\.\d+|\d+|[a-zA-Z]+|[()+\-*\/]/, input) |> List.flatten()
    stripped = String.replace(input, ~r/\s/, "")

    if stripped != "" and Enum.join(raw) == stripped do
      classify_all(raw)
    else
      {:error, :invalid_syntax}
    end
  end

  defp classify_all(raw) do
    raw
    |> Enum.reduce_while({:ok, []}, fn token, {:ok, acc} ->
      case classify(token) do
        {:ok, classified} -> {:cont, {:ok, [classified | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp classify("("), do: {:ok, :lparen}
  defp classify(")"), do: {:ok, :rparen}
  defp classify("+"), do: {:ok, {:op, :plus}}
  defp classify("-"), do: {:ok, {:op, :minus}}
  defp classify("*"), do: {:ok, {:op, :times}}
  defp classify("/"), do: {:ok, {:op, :divide}}

  defp classify(token) do
    cond do
      Regex.match?(~r/^\d/, token) -> {:ok, {:num, parse_number(token)}}
      Regex.match?(~r/^[a-zA-Z]+$/, token) -> classify_aggregation(token)
      true -> {:error, {:unexpected_token, token}}
    end
  end

  defp classify_aggregation(token) do
    case Map.fetch(@aggregations, String.downcase(token)) do
      {:ok, agg} -> {:ok, {:agg, agg}}
      :error -> {:error, {:unknown_aggregation, token}}
    end
  end

  defp parse_number(token) do
    if String.contains?(token, "."),
      do: String.to_float(token),
      else: String.to_integer(token)
  end
end
