# Copyright (c) 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: MIT
# Runs the built guest and judges it by its own RESULT lines.
#   elixir tools/test.exs godot     GODOT=<engine binary>, a real window, never --headless
#   elixir tools/test.exs rvlinux   RVLINUX=<libriscv-rs rvlinux binary>
#   elixir tools/test.exs limits    RVLINUX, and a witness checkout
#   elixir tools/test.exs hostlimits  GODOT; red while a host limit stands
defmodule Test do
  def main(argv) do
    File.cd!(Path.expand("..", __DIR__))

    case run(argv) do
      :ok -> System.halt(0)
      {:error, :control} -> System.halt(2)
      {:error, _} -> System.halt(1)
    end
  end

  defp run(["godot"]) do
    with {:ok, godot} <- env("GODOT"),
         :ok <- build(),
         {:ok, _} <- File.copy("build/guest.elf", "project/guest.elf") do
      cmd(godot, ["--path", "project", "--import", "--quit-after", "5"])
      {out, _} = cmd(godot, ["--path", "project", "--script", "run.gd", "--quit-after", "300"])
      show(out, ~r/RESULT|ERROR: Sandbox|hello from/)

      judge(out, [
        "RESULT: fib(30) == 832040",
        "RESULT: tasks sum == 33",
        "RESULT: vmcall add_numbers(3, 4) == 7"
      ])
      |> refuse(out, "ERROR: Sandbox")
    end
  end

  defp run(["rvlinux"]) do
    with {:ok, rvlinux} <- env("RVLINUX"), :ok <- build() do
      {out, _} = cmd(rvlinux, ["build/guest.elf"])
      IO.write(out)

      judge(out, [
        "RESULT: fib(30) == 832040",
        "RESULT: tasks sum == 33",
        "Program exited, exit code = 0 "
      ])
    end
  end

  defp run(["hostlimits"]) do
    with {:ok, godot} <- env("GODOT"),
         :ok <- build(),
         {:ok, _} <- File.copy("build/guest.elf", "project/guest.elf") do
      cmd(godot, ["--path", "project", "--import", "--quit-after", "5"])

      {out, _} =
        cmd(godot, ["--path", "project", "--script", "limits_host.gd", "--quit-after", "300"])

      show(out, ~r/^(PASS|FAIL|RESULT: \d)/)

      with :ok <- judge(out, ["RESULT: 0 falsified"]),
           :ok <- build(["tests/limits.mojo", "limits"], MOJO_FLAGS: "-I #{witness()}/src -I src"),
           {:ok, _} <- File.copy("build/limits.elf", "project/limits.elf") do
        {props, _} =
          cmd(godot, ["--path", "project", "--script", "limits_run.gd", "--quit-after", "300"])

        show(props, ~r/^(PASS|FAIL|SKIP|RESULT: \d)/)

        with :ok <- judge(props, ["PASS Wait_Timeout waits its deadline", "RESULT: 0 falsified"]),
             :ok <- build(["src/suspend.mojo", "suspend"]),
             {:ok, _} <- File.copy("build/suspend.elf", "project/suspend.elf") do
          {susp, _} =
            cmd(godot, ["--path", "project", "--script", "suspend_run.gd", "--quit-after", "400"])

          show(susp, ~r/^(PASS|FAIL|MEASURED|RESULT: \d)/)

          judge(susp, [
            "PASS start returns at once",
            "PASS not done when start returns",
            "PASS done after the host timer fires",
            "RESULT: 0 falsified"
          ])
        end
      end
    end
  end

  defp run(["limits"]) do
    witness = witness()

    with {:ok, rvlinux} <- env("RVLINUX"),
         :ok <- build(["tests/limits.mojo", "limits"], MOJO_FLAGS: "-I #{witness}/src -I src") do
      {out, _} = cmd(rvlinux, ["build/limits.elf"])
      show(out, ~r/.*/, 120)

      controls = ["PASS int round trip (control)", "PASS spin lock under tasks (control)"]

      cond do
        not Enum.all?(controls, &String.contains?(out, &1)) ->
          IO.puts(:stderr, "a control went red")
          {:error, :control}

        true ->
          judge(out, ["Program exited, exit code = 0 "])
      end
    end
  end

  defp run(_), do: {:error, :usage}

  defp witness do
    [System.get_env("WITNESS_REPO"), "../../2-contract/witness-mojo", "../contract-witness-mojo"]
    |> Enum.find(&(&1 && File.dir?(Path.join(&1, "src"))))
    |> Kernel.||("../contract-witness-mojo")
    |> Path.expand()
  end

  defp env(name) do
    case System.get_env(name) do
      nil -> {:error, {:unset, name}}
      value -> {:ok, value}
    end
  end

  defp build(args \\ [], env \\ []) do
    env = for {k, v} <- env, do: {to_string(k), v}

    case System.cmd("elixir", ["tools/build.exs" | args], env: env, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, status} -> IO.write(out) && {:error, {:build, status}}
    end
  end

  defp cmd(bin, args), do: System.cmd(bin, args, stderr_to_stdout: true)

  defp show(out, pattern, width \\ 400) do
    for line <- String.split(out, "\n"), line =~ pattern do
      IO.puts(String.slice(line, 0, width))
    end
  end

  defp judge(out, wanted) do
    case Enum.reject(wanted, &String.contains?(out, &1)) do
      [] -> :ok
      missing -> IO.puts(:stderr, "missing: #{inspect(missing)}") && {:error, :missing}
    end
  end

  defp refuse(:ok, out, text) do
    if String.contains?(out, text), do: {:error, {:found, text}}, else: :ok
  end

  defp refuse(error, _out, _text), do: error
end

Test.main(System.argv())
