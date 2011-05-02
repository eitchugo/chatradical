#!/usr/bin/ruby
# Este programa faz parte da aula de Sistemas Distribuídos da FIAP,
# e tem como intuito ser um cliente de um servidor de chat simples.
#
# O programa é executado de acordo com os argumentos 1 e 2, onde
# o 1 é o servidor e o 2 é o cliente. Caso não seja passado nenhum
# argumento de linha de comando, configura-se o 1 para localhost e
# o 2 para 7000.
#
# Author:: Hugo Cisneiros (Eitch) (mailto:hugo.cisneiros@gmail.com)
# License:: Do What The Fuck You Want To Public License

require 'socket'

# Esta classe contém todo o cliente de chat e é a única necessária
# para esta tarefa.
class ChatRadicalClient

    # Tenta conectar-se ao servidor utilizando o hostname e porta. Caso falhe,
    # o programa termina.
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

    # Mecanismo de handshake com o servidor para estabelecer uma conexão
    # válida no serviço de chat.
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

    # Escuta por comandos do usuário (via entrada padrão/STDIN) ou por
    # mensagens do servidor.
    #
    # * Para escutar por comandos do usuário via STDIN, usa-se uma nova
    # thread pois o Windows não suporta non-blocking IO para o STDIN.
    # * Usa-se o select() (non-blocking IO) para escutar as mensagens do
    # servidor constantemente.
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

    # Recebe as mensagens do servidor e decide o que fazer com elas,
    # chamando outros métodos.
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

    # De acordo com que o usuário digita na entrada padrão, chama outros
    # métodos que irão lidar com as requisições.
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
            return 0
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

    # Manda para o servidor a requisição de listar as salas disponíveis.
    def ListarSalas
        @server.puts "CMD_LISTCHN"
    end

    # Manda para o servidor a requisição de listar os usuários da sala atual.
    def ListarMembros
        @server.puts "CMD_WHOCHN"
    end

    # Manda para o servidor a requisição de mostrar informações da sala.
    def InfoSala
        @server.puts "CMD_INFOCHN"
    end

    # Manda para o servidor a requsição de entrar em uma sala.
    def EntrarSala(nome, descricao)
        @server.puts "CMD_JOINCHN #{nome} #{descricao}"
    end

    # Manda para o servidor a requisição de mostrar o registro de conversa
    # da sala.
    def VerLog(tail=nil)
        @server.puts "CMD_VLOG #{tail}"
    end

    # Manda para o servidor a requisição de mudança de apelido (nick).
    def MudarNick(nick)
        @server.puts "CMD_NICK #{nick}"
    end

    # Manda para o servidor a requisição de uma mensagem privada para um
    # usuário.
    def EnviarPVT(nick, msg)
        @server.puts "CMD_PVT #{nick} #{msg}"
    end

    # Manda para o servidor a requisição para finalizar a conexão com o
    # chat.
    def Desconectar
        puts "client> Saindo..."
        @server.puts "QUIT"
    end

    # Mostra na tela do cliente os comandos que o usuário pode utilizar.
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

    # Mostra na tela do cliente a mensagem de boas vindas (MOTD).
    def CliShowMotd
        while motd = @server.readline.chomp
            if motd =~ /^RCV_MOTD OK$/
                return 0
            else
                puts(motd)
            end
        end
    end

    # Mostra um erro na tela do cliente.
    def CliErro(msg)
        puts "error> #{msg}"
    end

    # Mostra o resultado da mudança de sala na tela do cliente.
    def CliMudancaSala(nome)
        puts "client> Mudando para a sala '#{nome}'"
    end

    # Mostra o resultado da lista de salas na tela do cliente.
    def CliListaSalas(rcv)
        puts "client> Salas disponíveis:"
        rcv.split('|').each do |sala|
            puts "client>    - #{sala}"
        end
    end

    # Mostra o resultado da lista de usuários da sala na tela do cliente.
    def CliListaUsuariosSala(rcv)
        puts "client> Usuarios na sala:"
        rcv.split('|').each do |membro|
            puts "client>    - #{membro}"
        end
    end

    # Mostra as informações da sala na tela do cliente.
    def CliInformacoesSala(nome, descricao)
        puts "client> Você está na sala #{nome} - #{descricao}"
    end

    # Mostra o resultado da mudança de nick na tela do cliente.
    def CliNick
        puts "client> Nick mudado."
    end

    # Mostra o resultado do envio de mensagem privada na tela do cliente.
    def CliPvtMsg
        puts "client> Mensagem enviada."
    end 

    # Mostra o resultado do registro de conversa da sala na tela do cliente.
    def CliChatLog(msg)
        puts msg
    end

    # Mostra uma mensagem recebida pelo servidor na tela do cliente.
    def CliChatMsg(msg)
        puts msg
    end
end

if ARGV.size == 2
   server = ARGV[0]
   port = ARGV[1]
else
   server = "localhost"
   port = 7000
end

client = ChatRadicalClient.new(server, port)
