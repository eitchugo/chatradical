#!/usr/bin/ruby
# 
# 
require 'socket'

class ChatRadicalClient
    def initialize(hostname, port)
        begin
            puts "client> Conectando-se ao servidor #{hostname}:#{port}..."
            @server = TCPSocket.open(hostname, port)
            puts "client> Conectado."
            Conectar()
            Listener()
            
        rescue EOFError
            puts "client> Conexão finalizada."
        rescue Interrupt
            puts "client> Usuário abortou o programa. Saindo..."
        rescue
            puts "error> Não foi possível conectar-se ao servidor!"
        ensure
            if @server
                @server.close
            end
        end
    end

    def Conectar()
 
        loop do
            print "Entre com seu nick: "
            nick = STDIN.gets.chomp
            print "Entre com seu nome: "
            nome = STDIN.gets.chomp

            # Manda a requisição pro servidor (handshake)
            @server.puts "CONN #{nick} #{nome}"
            resposta = @server.readline.chomp

            # Interpreta o retorno do handshake
            match = /^RCV_CONN (ERR (.+)|OK ([0-9]+))$/.match resposta
            if match[1] =~ /^ERR /
                CliErro(match[2])
            elsif match[1] =~ /^OK /
                puts "Conectado! Sua conexão é de número #{match[3]}."
                CliShowMotd()
                break
            end
        end
    end

    def Listener()

        # Thread do input do usuario
        Thread.new do
           loop do
               usercmd = STDIN.gets
               UserCMD(usercmd)
           end
        end

        # Infelizmente no Windows o select so atua em sockets, entao
        # STDIN fica na thread anterior
        loop do
            res = select([@server], nil, nil, nil)
            if res
                for inp in res[0]
                    if inp == @server
                        linha = @server.readline.chomp
                        RecebimentoDoServer(linha)
                    end
                end
            end
        end
    end

    def RecebimentoDoServer(linha)
        # Quando mudou de sala
        match = /^RCV_JOINCHN (ERR (.*)|OK ([\w]+))$/.match linha
        if match
            if match[1] =~ /^ERR /
                CliErro(match[2])
                return 1
            else
                CliMudancaSala(match[3])
                return 0
            end
        end

        # Listar todas as salas do servidor
        match = /^RCV_LISTCHN (ERR (.+)|OK (.+))$/.match linha
        if match
            if match[1] =~ /^ERR /
                CliErro(match[2])
                return 1
            else
                CliListaSalas(match[3])
                return 0
            end
        end

        # Lista usuarios da sala atual
        match = /^RCV_WHOCHN (ERR (.+)|OK (.+))$/.match linha
        if match
            if match[1] =~ /^ERR /
                CliErro(match[2])
                return 1
            else
                CliListaUsuariosSala(match[3])
                return 0
            end
        end

        # Informações sobre a sala
        match = /^RCV_INFOCHN (ERR (.+)|OK ([a-zA-Z0-9]{1,24}) (.+))$/.match linha
        if match
            if match[1] =~ /^ERR /
                CliErro(match[2])
                return 1
            else
                CliInformacoesSala(match[3], match[4])
                return 0
            end
        end

        # Mudança de nick
        match = /^RCV_NICK (ERR (.*)|OK)/.match linha
        if match
            if match[1] =~ /^ERR /
                CliErro(match[2])
                return 1
            else
                CliNick()
                return 0
            end
        end

        # Mensagem privada 
        match = /^RCV_PVT (ERR (.*)|OK)/.match linha
        if match
            if match[1] =~ /^ERR /
                CliErro(match[2])
                return 1
            else
                CliPvtMsg()
                return 0
            end
        end

        # Log de mensagens da sala
        match = /^RCV_CHATLOG (.+)/.match linha
        if match
            CliChatLog(match[1])
            return 0
        end

        # Mensagens de chat
        match = /^RCV_CHATMSG (.+)/.match linha
        if match
            CliChatMsg(match[1])
            return 0
        end
    end

    def UserCMD(linha)
        # Listar salas
        match = /^\/list( |$)/i.match linha
        if match
            ListarSalas()
            return 0
        end

        # Listar Usuarios da sala atual
        match = /^\/who( |$)/i.match linha
        if match
            ListarMembros()
            return 0
        end

        # Entrar em uma sala (criar se nao existir)
        match = /^\/join ([a-zA-Z0-9]{1,24})( (.+))?/i.match linha
        if match
            EntrarSala(match[1], match[3])
            return 0
        end

        # Informações da sala atual
        match = /^\/info( |$)/i.match linha
        if match
            InfoSala()
            return 0
        end

        # Mudança de nick
        match = /^\/nick ([a-zA-Z0-9]{1,24})$/.match linha
        if match
            MudarNick(match[1])
            return 0
        end

        # Envio de mensagem privada
        match = /^\/msg ([a-zA-Z0-9]{1,24}) (.+)/.match linha
        if match
            EnviarPVT(match[1], match[2])
            return 0
        end

        # Log de conversa da sala atual
        match = /^\/log( ([0-9]{1,2})|$)/i.match linha
        if match
            if match[2]
                VerLog(match[2])
            else
                VerLog()
            end
            return 0
        end

        # Sair do chat
        match = /^\/quit( |$)/i.match linha
        if match
            Desconectar()
        end

        # Ajuda
        match = /^\/help( |$)/i.match linha
        if match
            CliAjuda()
            return 0
        end

        # Comandos invalidos
        match = /^\//i.match linha
        if match
            CliErro('Comando inválido!')
            return 1
        end

        # Tudo o mais é mensagem de chat
        @server.puts "CMD_CHAT #{linha}"
        return 0
    end

    def ListarSalas
        @server.puts "CMD_LISTCHN"
    end

    def ListarMembros
        @server.puts "CMD_WHOCHN"
    end

    def InfoSala
        @server.puts "CMD_INFOCHN"
    end

    def EntrarSala(nome, descricao)
        @server.puts "CMD_JOINCHN #{nome} #{descricao}"
    end

    def VerLog(tail=nil)
        @server.puts "CMD_VLOG #{tail}"
    end

    def MudarNick(nick)
        @server.puts "CMD_NICK #{nick}"
    end

    def EnviarPVT(nick, msg)
        @server.puts "CMD_PVT #{nick} #{msg}"
    end

    def Desconectar
        puts "client> Saindo..."
        @server.puts "QUIT"
    end

    def CliAjuda
        puts "cliente> Ajuda!"
        puts "   * /list - Lista os canais"
        puts "   * /join <sala> [descricao] - Entra na sala, se nao existir cria um novo"
        puts "   * /who - Mostra quem tá na sala atual"
        puts "   * /info - Mostra o nome da sala atual e sua descrição"
        puts "   * /log [n] - Mostra n número de linhas de histórico da sala (padrão 30)"
        puts "   * /msg <nick> <msg> - Manda uma mensagem privada para alguém"
        puts "   * /nick <novo_nick> - Muda o seu nick"
        puts "   * /quit - Sai do servidor"
    end

    def CliShowMotd
        while motd = @server.readline.chomp
            if motd =~ /^RCV_MOTD OK$/
                return 0
            else
                puts(motd)
            end
        end
    end

    def CliErro(msg)
        puts "error> #{msg}"
    end

    def CliMudancaSala(nome)
        puts "client> Mudando para a sala '#{nome}'"
    end

    def CliListaSalas(rcv)
        puts "client> Salas disponíveis:"
        rcv.split('|').each do |sala|
            puts "client>    - #{sala}"
        end
    end

    def CliListaUsuariosSala(rcv)
        puts "client> Usuarios na sala:"
        rcv.split('|').each do |membro|
            puts "client>    - #{membro}"
        end
    end

    def CliInformacoesSala(nome, descricao)
        puts "client> Você está na sala #{nome} - #{descricao}"
    end

    def CliNick
        puts "client> Nick mudado."
    end

    def CliPvtMsg
        puts "client> Mensagem enviada."
    end 

    def CliChatLog(msg)
        puts msg
    end

    def CliChatMsg(msg)
        puts msg
    end
end

# Executa o programa de acordo com os argumentos
# Padrão vai para localhost, porta 7000
if ARGV.size == 2
   server = ARGV[0]
   port = ARGV[1]
else
   server = "localhost"
   port = 7000
end

client = ChatRadicalClient.new(server, port)
