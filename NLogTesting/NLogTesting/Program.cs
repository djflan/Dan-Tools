using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using NLog;

namespace NLogTesting
{
    internal class Program
    {
        private const string LoggerName = "apiContentLog";
        private static readonly NLog.Logger Logger = NLog.LogManager.GetLogger(LoggerName);

        private static void Main()
        {
            var x = NLog.LogManager.Configuration;
            Logger.Log(new LogEventInfo(LogLevel.Debug, LoggerName, "test"));
        }
    }
}
