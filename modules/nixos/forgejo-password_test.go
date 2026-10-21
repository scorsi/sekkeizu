package cmd

import (
	"context"
	"testing"

	"github.com/urfave/cli/v3"
)

func TestSekkeizuAdminPasswordEnvironment(t *testing.T) {
	const password = "fixture password with spaces & symbols!"
	t.Setenv("FORGEJO_ADMIN_PASSWORD", password)
	for _, command := range []*cli.Command{microcmdUserCreate(), microcmdUserChangePassword()} {
		t.Run(command.Name, func(t *testing.T) {
			called := false
			command.Action = func(_ context.Context, c *cli.Command) error {
				called = true
				if !c.IsSet("password") || c.String("password") != password {
					t.Fatal("password environment source was not applied")
				}
				return nil
			}
			if err := command.Run(context.Background(), []string{command.Name}); err != nil {
				t.Fatal(err)
			}
			if !called {
				t.Fatal("admin command was not invoked")
			}
		})
	}
}
