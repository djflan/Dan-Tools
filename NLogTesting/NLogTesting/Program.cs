using NLog;

namespace NLogTesting
{
    internal class Program
    {
        private const string LoggerName = "PatientAccessApiContent";
        private static readonly NLog.Logger Logger = NLog.LogManager.GetLogger(LoggerName);

        private static void Main()
        {
            Log("Basic text logging");
        }

        private static void Log(string message)
        {
            Logger.Log(new LogEventInfo(LogLevel.Debug, LoggerName, message));
        }
    }
}
