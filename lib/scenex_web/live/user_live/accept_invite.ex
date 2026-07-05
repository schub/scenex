defmodule ScenexWeb.UserLive.AcceptInvite do
  @moduledoc """
  Accept a scenario invitation — the only account-creation path now that
  public registration is closed.

  The emailed token resolves to a pending `ScenarioInvitation`. New invitees
  set a password and get a confirmed account + membership in one step, then
  are logged in by posting the same credentials to the session controller
  (`phx-trigger-action`). Edge cases: an account that appeared after the
  invite was sent just gains the membership; a logged-in user with the
  invited email accepts directly.
  """
  use ScenexWeb, :live_view

  alias Scenex.Accounts.User
  alias Scenex.Authoring

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            Join "{@scenario_name}"
            <:subtitle>
              You've been invited as <span class="font-semibold">{@invitation.role}</span>.
              Choose a password to create your account.
            </:subtitle>
          </.header>
        </div>

        <.form
          for={@form}
          id="accept_invite_form"
          action={~p"/users/log-in"}
          phx-submit="save"
          phx-change="validate"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            value={@invitation.email}
            readonly
            autocomplete="username"
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="new-password"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm password"
            autocomplete="new-password"
            required
          />
          <.button phx-disable-with="Joining..." class="btn btn-primary w-full">
            Create account & join
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Authoring.get_invitation_by_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Invitation link is invalid or it has expired.")
         |> push_navigate(to: ~p"/users/log-in")}

      invitation ->
        scenario_name =
          Scenex.I18n.t!(invitation.scenario.name, invitation.scenario.source_locale,
            default: invitation.scenario.handle
          )

        current_user = socket.assigns.current_scope && socket.assigns.current_scope.user

        cond do
          # Logged in with the invited email: accept immediately, no form.
          current_user && current_user.email == invitation.email ->
            {:ok, _} = Authoring.accept_invitation(invitation, %{})

            {:ok,
             socket
             |> put_flash(:info, "You've joined \"#{scenario_name}\".")
             |> push_navigate(to: ~p"/scenarios/#{invitation.scenario_id}")}

          # Logged in as someone else: don't silently attach the wrong account.
          current_user ->
            {:ok,
             socket
             |> put_flash(
               :error,
               "This invitation was sent to #{invitation.email}, but you are " <>
                 "logged in as #{current_user.email}. Log out first to accept it."
             )
             |> push_navigate(to: ~p"/scenarios")}

          true ->
            changeset = password_changeset(%{})

            {:ok,
             socket
             |> assign(
               invitation: invitation,
               scenario_name: scenario_name,
               trigger_submit: false
             )
             |> assign_form(changeset)}
        end
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset = params |> password_changeset() |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Authoring.accept_invitation(socket.assigns.invitation, params) do
      {:ok, :existing_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "You already have an account — log in to see the scenario.")
         |> push_navigate(to: ~p"/users/log-in")}

      {:ok, %User{}} ->
        # Account created. Re-assign the form with the submitted params so the
        # re-rendered inputs still carry the credentials, then let the browser
        # POST them to the session controller — the user lands logged in.
        {:noreply,
         socket
         |> assign(trigger_submit: true)
         |> assign_form(password_changeset(params))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  # Validation-only changeset (no hashing) for live feedback.
  defp password_changeset(params) do
    User.password_changeset(%User{}, params, hash_password: false)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "user"))
  end
end
