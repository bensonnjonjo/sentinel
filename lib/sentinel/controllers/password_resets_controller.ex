defmodule Sentinel.Controllers.PasswordResets do
  use Phoenix.Controller
  use Guardian.Phoenix.Controller

  alias Sentinel.PasswordResetter
  alias Sentinel.Mailer
  alias Sentinel.Util
  alias Sentinel.UserHelper

  @doc """
  Create a password reset token for a user
  Params should be:
  {email: "user@example.com"}
  If successfull, sends an email with instructions on how to reset the password.
  Responds with status 200 and body "ok" if successful or not, for security.
  """
  def create(conn, %{"email" => email}, _headers \\ %{}, _session \\ %{}) do
    user = UserHelper.find_by_email(email)
    {password_reset_token, changeset} = PasswordResetter.create_changeset(user)

    if changeset.valid? do
      user = Util.repo.update!(changeset)
      Mailer.send_password_reset_email(user, password_reset_token)
    end

    json conn, :ok
  end

  @doc """
  Resets a users password if the provided token matches
  Params should be:
  {user_id: 1, password_reset_token: "abc123"}
  Responds with status 200 and body {token: token} if successfull. Use this token in subsequent requests as authentication.
  Responds with status 422 and body {errors: [messages]} otherwise.
  """
  def reset(conn, params = %{"user_id" => user_id}, _headers \\%{}, _session \\ %{}) do
    user = Util.repo.get(UserHelper.model, user_id)
    changeset = PasswordResetter.reset_changeset(user, params)

    if changeset.valid? do
      user = Util.repo.update!(changeset)
      permissions = UserHelper.model.permissions(user.role)

      case Guardian.encode_and_sign(user, :token, permissions) do
        { :ok, token, _encoded_claims } -> json conn, %{token: token}
        { :error, :token_storage_failure } -> Util.send_error(conn, %{errors: "Failed to store session, please try to login again using your new password"})
        { :error, reason } -> Util.send_error(conn, %{errors: reason})
      end
    else
      Util.send_error(conn, Enum.into(changeset.errors, %{}))
    end
  end
end
