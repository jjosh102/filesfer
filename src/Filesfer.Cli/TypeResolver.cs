using Spectre.Console.Cli;
namespace Filesfer.Cli;

public sealed class TypeResolver : ITypeResolver, IDisposable
{
    private readonly IServiceProvider _provider;

    public TypeResolver(IServiceProvider provider)
    {
        ArgumentNullException.ThrowIfNull(provider);
        _provider = provider;
    }

    public object? Resolve(Type? type) =>
        type == null ? null : _provider.GetService(type);

    public void Dispose()
    {
        if (_provider is IDisposable disposable)
        {
            disposable.Dispose();
        }
    }
}