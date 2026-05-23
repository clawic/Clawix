using System.Text;
using Clawix.Core;
using Clawix.Secrets.Models;
using Clawix.Secrets.Vault;

namespace Clawix.App.Services;

public sealed class WindowsSecretsVaultService : IDisposable
{
    private const string RecoveryPhraseKey = "secrets.recoveryPhrase";
    private static readonly byte[] KeyDerivationSalt = Encoding.UTF8.GetBytes("clawix-windows-secrets-vault-v1");

    private readonly CredentialStore _credentials;
    private readonly Vault _vault;
    private bool _lockedByUser;

    public WindowsSecretsVaultService(CredentialStore credentials)
    {
        _credentials = credentials;
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var dir = Path.Combine(appData, "Clawix");
        Directory.CreateDirectory(dir);
        _vault = new Vault(Path.Combine(dir, "secrets.sqlite"));
    }

    public bool IsUnlocked => _vault.IsUnlocked;

    public string RecoveryPhrase => EnsureRecoveryPhrase();

    public IReadOnlyList<Secret> List()
    {
        EnsureUnlocked();
        return _vault.List();
    }

    public void Add(string label, SecretKind kind, string value)
    {
        EnsureUnlocked();
        var normalizedLabel = label.Trim();
        if (normalizedLabel.Length == 0)
            throw new ArgumentException("Secret label is required.", nameof(label));
        if (string.IsNullOrEmpty(value))
            throw new ArgumentException("Secret value is required.", nameof(value));

        _vault.Add(normalizedLabel, kind, value);
    }

    public void Lock()
    {
        _lockedByUser = true;
        _vault.Lock();
    }

    public void Dispose() => _vault.Dispose();

    private void EnsureUnlocked()
    {
        if (_vault.IsUnlocked) return;
        if (_lockedByUser) throw new InvalidOperationException("Secrets vault is locked. Restart Clawix to unlock it from Windows Credential Manager.");
        _vault.Unlock(EnsureRecoveryPhrase(), KeyDerivationSalt);
    }

    private string EnsureRecoveryPhrase()
    {
        var phrase = _credentials.Read(RecoveryPhraseKey);
        if (!string.IsNullOrWhiteSpace(phrase)) return phrase;

        phrase = WindowsSecretsRecoveryPhrase.Generate();
        _credentials.Write(RecoveryPhraseKey, phrase);
        return phrase;
    }
}
