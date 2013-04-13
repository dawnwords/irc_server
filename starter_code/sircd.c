/* To compile: gcc sircd.c rtlib.c rtgrading.c csapp.c -lpthread -osircd */
#define _GNU_SOURCE

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <arpa/inet.h>
#include <sys/times.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <unistd.h>
#include <regex.h>
#include "csapp.h"
#include "rtlib.h"
#include "rtgrading.h"


/* Macros */
#define MAX_MSG_TOKENS 10
#define MAX_MSG_LEN 512
#define LIMIT_MSG_LEG 480
#define MAX_NAME_LENGTH 9

/* command */
#define USER_CMD 0
#define NICK_CMD 1
#define QUIT_CMD 2
#define JOIN_CMD 3
#define PART_CMD 4
#define LIST_CMD 5
#define WHO_CMD 6
#define PRIVMSG_CMD 7
#define UNKONWN_CMD -1

const int ARG_NUM[8] = {4,1,0,1,1,0,1,2};

typedef struct {                    /* represents a pool of connected descriptors */
    int maxfd;                      /* largest descriptor in read_set */
    fd_set read_set;                /* set of all active descriptors */
    fd_set ready_set;               /* subset of descriptors ready for reading  */
    int nready;                     /* number of ready descriptors from select */
    int maxi;                       /* highwater index into client array */
    int clientfd[FD_SETSIZE];       /* set of active descriptors */
    rio_t clientrio[FD_SETSIZE];    /* set of active read buffers */
} pool;

typedef struct fd_list_struct{
    int fd;
    struct fd_list_struct* next;
} fd_list;

typedef struct channel_struct{
    char* name;
    fd_list* member;
    struct channel_struct* prev;
    struct channel_struct* next;
} channel;

typedef struct user_struct{
    char* user_name;
    char* nick_name;
    char* host_name;
    char* server_name;
    char* real_name;
    channel* located_channel;
} user;


/* Global variables */
u_long curr_nodeID;
rt_config_file_t   curr_node_config_file;  /* The config_file  for this node */
rt_config_entry_t *curr_node_config_entry; /* The config_entry for this node */

pool p;

channel *header, *footer; /* the header and footer of the linked list of struct channel */

user* user_table[FD_SETSIZE]; /* the user table with users locates at its 'clientfd' position */

/* Function prototypes */
void init_node( int argc, char *argv[] );
size_t get_msg( char *buf, char *msg );
int tokenize( char const *in_buf, char tokens[MAX_MSG_TOKENS][MAX_MSG_LEN+1] );

void init_pool(int listenfd);
void add_client(int connfd);
void check_clients();
void unblock_socket(int socketfd);

/* message handler */
void nick_command(int connfd,char* nick_name);
void user_command(int connfd,char* user_name, char* real_name);
void join_command(int connfd,char* channel_name);
void part_command(int connfd,char* channel_name,int need_writeback);
void quit_command(int connfd);
void list_command(int connfd);
void who_command(int connfd,char *match);
void privmsg_command(int connfd,char *target,char* msg);
void unknown_command(int connfd, char* cmd);

/* data structure operating function */
void init_channel_user();
int find_user(char* name, int connfd);
channel* find_channel(char *name);
channel* create_channel(char* name);
void remove_channel(channel* channel);
void invoke_channel(int connfd,char *msg, channel* c);

void add_fd_list(fd_list* list, int fd);
int remove_fd_list(fd_list* list, int fd);

void free_user(user* u);
void free_channel(channel* c);

/* DEBUG FUNCTIONS */
int show_channel(char* result, int max,channel* c);
void debug_list_all_user();
int show_user(char* result,int max,user* u);
void debug_list_all_channel();

int main(int argc, char **argv) {
    int listenfd, connfd, port;
    socklen_t clientlen = sizeof(struct sockaddr_in);
    struct sockaddr_in clientaddr;
    user* u;

    /* Init node and set port accoriding to configue file */
    init_node(argc, argv);
    port = curr_node_config_entry->irc_port;

    /* Init the linked list of channel and the table of user */
    init_channel_user();

    printf( "I am node %lu and I listen on port %d for new users\n", curr_nodeID, port);
    /* Init server socket and set it as unblocked */
    listenfd = Open_listenfd(port);
    unblock_socket(listenfd);

    /* Init struct pool */
    init_pool(listenfd);
    while (1) {
        /* Wait for listening/connected descriptor(s) to become ready */
        p.ready_set = p.read_set;
        p.nready = Select(p.maxfd+1, &p.ready_set, NULL, NULL, NULL);

        /* If listening descriptor ready, add new client to pool */
        if (FD_ISSET(listenfd, &p.ready_set)) {
            connfd = Accept(listenfd, (SA *)&clientaddr, &clientlen);

            /* create a user struct for the connect fd */
            u = (user*) Calloc(1,sizeof(user));
            user_table[connfd] = u;

            /*set server_name and host_name for user */
            u->host_name = strdup(Gethostbyaddr((const char*)&clientaddr.sin_addr,sizeof(clientaddr.sin_addr),AF_INET)->h_name);
            u->server_name = strdup(Gethostbyname("localhost")->h_name);

            add_client(connfd);
        }

        /* Echo a text line from each ready connected descriptor */
        check_clients();
    }
}

void unblock_socket(int socketfd){
     /* flag value for setsockopt */
    int opts = 1;
    setsockopt(socketfd, SOL_SOCKET, SO_REUSEADDR, (const void *)&opts , sizeof(int));

    /* getting current options */
    if ((opts = fcntl(socketfd, F_GETFL)) < 0)
        unix_error("Error on fcntl\n");

    /* modifying and applying */
    opts = (opts | O_NONBLOCK);
    if (fcntl(socketfd, F_SETFL, opts))
        unix_error("Error on fcntl\n");
}

void init_pool(int listenfd) {
    /* Initially, there are no connected descriptors */
    int i;
    p.maxi = -1;
    for (i=0; i< FD_SETSIZE; i++)
        p.clientfd[i] = -1;

    /* Initially, listenfd is only member of select read set */
    p.maxfd = listenfd;
    FD_ZERO(&p.read_set);
    FD_SET(listenfd, &p.read_set);
}

void add_client(int connfd) {
    int i;
    p.nready--;
    for (i = 0; i < FD_SETSIZE; i++)  /* Find an available slot */
        if (p.clientfd[i] < 0) {
            /* Add connected descriptor to the pool */
            p.clientfd[i] = connfd;
            Rio_readinitb(&p.clientrio[i], connfd);

            /* Add the descriptor to descriptor set */
            FD_SET(connfd, &p.read_set);

            /* Update max descriptor and pool highwater mark */
            if (connfd > p.maxfd)
                p.maxfd = connfd;
            if (i > p.maxi)
                p.maxi = i;
            break;
        }
    if (i == FD_SETSIZE) /* Couldn't find an empty slot */
        app_error("add_client error: Too many clients");
}

void send_msg_back(int connfd,char* msg){
    //DEBUG
    printf(" # MSG BACK TO %d:\n\t%s\n", connfd,msg);
    rio_writen(connfd,msg,strlen(msg));
}

int check_register(int connfd){
    user* u = user_table[connfd];
    if(u->user_name && u->nick_name && u->real_name)
        return 1;
    else        
        return 0; 
}

void request_check(int index, char* buf, char tokens[MAX_MSG_TOKENS][MAX_MSG_LEN+1]){
    int arg_num = tokenize(buf,tokens);
    int type,connfd;

    connfd = p.clientfd[index];

    if (!strcmp(tokens[0],"USER"))
        type = USER_CMD;
    else if(!strcmp(tokens[0],"NICK"))
        type = NICK_CMD;
    else if(!strcmp(tokens[0],"JOIN"))
        type = JOIN_CMD;
    else if(!strcmp(tokens[0],"QUIT"))
        type = QUIT_CMD;
    else if(!strcmp(tokens[0],"PART"))
        type = PART_CMD;
    else if(!strcmp(tokens[0],"LIST"))
        type = LIST_CMD;
    else if(!strcmp(tokens[0],"WHO"))
        type = WHO_CMD;
    else if(!strcmp(tokens[0],"PRIVMSG"))
        type = PRIVMSG_CMD;
    else
        type = UNKONWN_CMD;

    //DEBUG
    int i;
    printf(" # CMD:%s\t ARG_NUM:%d\t",tokens[0],arg_num);
    for(i=0;i<4;i++)
        printf(" ARG%d:%s\t",i,tokens[i+1]);
    printf("\n");

    if(type == UNKONWN_CMD)
        unknown_command(connfd,tokens[0]);
    else if(arg_num < ARG_NUM[type]){
        char msg[MAX_MSG_LEN];
        if(type == NICK_CMD)
            /* NICK ERRRO TYPE: ERR_NOERR_NONICKNAMEGIVEN */
            snprintf(msg,MAX_MSG_LEN,":No nickname given\n");
        else if(type == PRIVMSG_CMD){
            /* PRIVMSG ERRRO TYPE: ERR_NORECIPIENT */
            if(!arg_num)
                snprintf(msg,MAX_MSG_LEN,":No recipient given PRIVMSG\n");
            /* PRIVMSG ERRRO TYPE: ERR_NOTEXTTOSEND */
            else
                snprintf(msg,MAX_MSG_LEN,":No text to send\n");
        }else
            snprintf(msg,MAX_MSG_LEN,"%s:Not enough parameters\n", tokens[0]);
        send_msg_back(connfd,msg);
    }
    else
        switch(type){
            case QUIT_CMD:
                quit_command(index);
                break;
            case USER_CMD:
                user_command(connfd,tokens[1],tokens[4]);               
                break;
            case NICK_CMD:
                nick_command(connfd,tokens[1]);
                break;
            default:
                if(check_register(connfd)){
                    switch(type){
                        case JOIN_CMD:
                            join_command(connfd,tokens[1]);
                            break;
                        case PART_CMD:
                            part_command(connfd,tokens[1],1);
                            break;
                        case LIST_CMD:
                            list_command(connfd);
                            break;
                        case WHO_CMD:
                            who_command(connfd,tokens[1]);
                            break;
                        case PRIVMSG_CMD:
                            privmsg_command(connfd,tokens[1],tokens[2]);
                    }
                }else
                    send_msg_back(connfd,":You have not registered\n");
        }
}

void check_clients() {
    int i, connfd;
    char buf[MAXLINE];
    rio_t rio;

    for (i = 0; (i <= p.maxi) && (p.nready > 0); i++) {
        connfd = p.clientfd[i];
        rio = p.clientrio[i];

        if ((connfd > 0) && FD_ISSET(connfd, &p.ready_set)){
            p.nready--;
            if (rio_readlineb(&rio, buf, MAXLINE) > 0) {
                char tokens[MAX_MSG_TOKENS][MAX_MSG_LEN+1];
                get_msg(buf,buf);
                request_check(i, buf, tokens);
            } else{/* EOF detected. User Exit */
                //debug
                char buf[MAX_MSG_LEN];
                show_user(buf,MAX_MSG_LEN,user_table[connfd]);
                printf("!!Exit%s\n", buf);

                /* do quit command for user at connfd[i] */
                quit_command(i);
            }
            //debug
            debug_list_all_user();
            debug_list_all_channel();
            printf("===================================\n");
        }
    }
}

void show_motd(int connfd){
    char MOTD[MAX_MSG_LEN];
    user* u = user_table[connfd];
    int length = 0;

    length += snprintf(MOTD+length, MAX_MSG_LEN-length,":IRC_SERVER 375 %s :- Hello! Message of the day -  \n",u->nick_name);
    length += snprintf(MOTD+length, MAX_MSG_LEN-length,":IRC_SERVER 372 %s :- Welcome to Use IRC Server!\n",u->nick_name);
    length += snprintf(MOTD+length, MAX_MSG_LEN-length,":IRC_SERVER 376 %s :End of /MOTD command\n",u->nick_name);

    send_msg_back(connfd,MOTD);
}

void unknown_command(int connfd, char* cmd){
    char msg[MAX_MSG_LEN];
    snprintf(msg, MAX_MSG_LEN, "%s: Unknown command\n",cmd);
    send_msg_back(connfd,msg);
}

int nick_valid_char(char c){
    if((c>='a' && c<='z') || (c>='A' && c<='Z') || (c>='0' && c<='9') ||
        c=='-' || c=='[' || c==']' || c=='\\' || c=='`' || c=='^' || c=='{' || c=='}')
        return 1;
    else
        return 0;
}

int nick_valid(char* name){
    int i;
    if(strlen(name)>MAX_NAME_LENGTH)
        return 0;
    for(i=0;i<strlen(name);i++)
        if(!nick_valid_char(name[i]))
            return 0;
    return 1;
}

void nick_command(int connfd,char* nick_name){
    int length = 0;
    char msg[MAX_MSG_LEN];

    if(!nick_valid(nick_name))
        length += snprintf(msg,MAX_MSG_LEN,"%s:Erroneus nickname\n",nick_name);
    else{
        /* if nick name has not been used, give it to current user */
        if(find_user(nick_name,connfd) < 0){
            user* u = user_table[connfd];
            /* USER without NICK*/
            if(!u->nick_name && u->user_name && u->real_name){
                u->nick_name = strdup(nick_name);
                show_motd(connfd);
            }else
                u->nick_name = strdup(nick_name);
        } else
            length += snprintf(msg,MAX_MSG_LEN,"%s:Nickname is already in use\n",nick_name);
    }       

    if(length > 0)
        send_msg_back(connfd,msg);        
}

void user_command(int connfd, char* user_name, char* real_name){
    
    /* get user struct by connfd */
    user* u = user_table[connfd];
    int length = 0;
    char msg[MAX_MSG_LEN];
    if(u->real_name && u->user_name)
        length += snprintf(msg,MAX_MSG_LEN,":You may not reregister\n");
    else{
        if(u->nick_name && !u->user_name && !u->real_name){
            /* set username and realname for u*/
            u->user_name = strdup(user_name);
            u->real_name = strdup(real_name);
            show_motd(connfd);
        }else{
            /* set username and realname for u*/
            u->user_name = strdup(user_name);
            u->real_name = strdup(real_name);
        }          
    }
    
    if(length > 0)
        send_msg_back(connfd,msg);
}

void quit_command(int index){
    int connfd = p.clientfd[index];
    user* u;
    if((u = user_table[connfd])){
        if(u->located_channel)
            part_command(connfd,u->located_channel->name,0);
        free_user(u);
        user_table[connfd] = NULL;
    }

    close(connfd);
    FD_CLR(connfd, &p.read_set);
    p.clientfd[index] = -1;
}

int channel_valid_char(char c){
    if(c == ' ' || c == '\7' || c == '\0' || c== '\13' || c== '\10' || c==',')
        return 0;
    return 1;
}

int channel_valid(char* name){
    if(strlen(name)>MAX_NAME_LENGTH || (name[0]!='#' && name[0]!='&'))
        return 0;
    int i;
    for(i=1;i<strlen(name);i++)
        if(!channel_valid_char(name[i]))
            return 0;
    return 1;
}

void join_command(int connfd,char* channel_name){
    int length = 0;
    char back[MAX_MSG_LEN];

    if(channel_valid(channel_name)){
        /* if located channel exisits, part command is needed first */
        user *u = user_table[connfd];
        if(u->located_channel){
            /* JOIN the same channel twice should be ignore */
            if(!strcasecmp(u->located_channel->name,channel_name))
                return;
            /* otherwise should PART the orignal channel first */
            part_command(connfd,u->located_channel->name,1);
        }        

        /* try to create a channel with the name of 'channel_name' */
        u->located_channel = create_channel(channel_name);    

        /* echo to all member */
        length += snprintf(back + length, MAX_MSG_LEN - length, ":%s JOIN %s\n",u->nick_name,u->located_channel->name);
        invoke_channel(connfd,back,u->located_channel);

        /* add connfd into the channel list */
        add_fd_list(u->located_channel->member,connfd);

        /* write the list in the channel back back */
        fd_list* ufd;
        user* channelu;
        for(ufd = u->located_channel->member->next;ufd;ufd = ufd->next){
            channelu = user_table[ufd->fd];

            length += snprintf(back + length, MAX_MSG_LEN - length, ":IRC_SERVER 353 %s = %s:%s\n",
                u->nick_name,channelu->located_channel->name,channelu->nick_name);
        }
            
        length += snprintf(back + length, MAX_MSG_LEN - length, ":IRC_SERVER 366 %s %s :End of /NAMES list\n",u->nick_name,u->located_channel->name);
    }else
        snprintf(back, MAX_MSG_LEN, "%s:No such channel\n",channel_name);
   
    send_msg_back(connfd,back);
}

void part_command(int connfd,char* channel_name,int need_writeback){
    char msg[MAX_MSG_LEN];

    /* find user of self */
    user *u = user_table[connfd];
    channel *c = u->located_channel;
    
    if(!find_channel(channel_name))
        snprintf(msg,MAX_MSG_LEN,"%s:No such channel\n",channel_name);
    else if(!c || !c->name || strcasecmp(channel_name,c->name))
        snprintf(msg,MAX_MSG_LEN,"%s:You're not on that channel\n",channel_name);
    else{
        snprintf(msg,MAX_MSG_LEN,":%s!%s@%s QUIT: See You!~\n",u->nick_name,u->user_name,u->host_name);
        /* if the channel has no one left, then remove it out*/
        int size = remove_fd_list(c->member,connfd);
        if(size == 0)
            remove_channel(c);
        
        /* if there is still someone at the channel, send a message to tell them 'u' has left */
        else
            invoke_channel(connfd, msg, c); 
        
        /* set located channel to null*/
        u->located_channel = NULL;
    }
    if(need_writeback)
        send_msg_back(connfd,msg);
}

void list_command(int connfd){
    int length = 0;
    char buf[MAX_MSG_LEN];
    channel *c;
    user *self = user_table[connfd];

    length += snprintf(buf + length, MAX_MSG_LEN - length, ":IRC_SERVER 321 %s Channel :Users Name\n",self->nick_name);
    /* traverse all the channels to list its name and number of users */
    for(c = header->next; c->next; c=c->next)
        length += snprintf(buf + length, MAX_MSG_LEN - length, ":IRC_SERVER 322 %s %s %d\n",
                self->nick_name,c->name, c->member->fd);

    length += snprintf(buf + length, MAX_MSG_LEN - length, ":IRC_SERVER 323 %s :End of /LIST\n",self->nick_name);
    send_msg_back(connfd,buf);
}

void who_command(int connfd,char *match){    
    int length = 0;
    char buf[MAX_MSG_LEN];
    channel* c;
    user *u;
    user* self = user_table[connfd];

    /* traverse channel list to find name match */
    if((c = find_channel(match))) {
        fd_list *temp;
        for (temp = c->member->next;temp;temp = temp->next){
            u = user_table[temp->fd];
            length += snprintf(buf + length, MAX_MSG_LEN - length, ":IRC_SERVER 352 %s %s %s %s %s %s H :%d %s\n",
                self->nick_name,u->located_channel->name,u->user_name,u->host_name,u->server_name,u->nick_name,0,u->real_name);
        }
    }

    /* if no such channel matches, traverse users to find name match */
    else {
        int i;
        for (i = 0; i <= p.maxi; i++) {
            u = user_table[p.clientfd[i]];
            if(u && u->user_name && u->server_name && u->host_name && u->real_name && u->nick_name &&
                (!strcasecmp(u->user_name,match) ||!strcasecmp(u->server_name,match) || !strcasecmp(u->host_name,match) ||
                !strcasecmp(u->real_name,match) || !strcasecmp(u->nick_name,match))){
                length += snprintf(buf + length, MAX_MSG_LEN - length, ":IRC_SERVER 352 %s %s %s %s %s %s H :%d %s\n",
                    self->nick_name,u->located_channel->name,u->user_name,u->host_name,u->server_name,u->nick_name,0,u->real_name);
            }
        }
    }

    length += snprintf(buf + length, MAX_MSG_LEN - length, ":IRC_SERVER 315 %s %s :End of /WHO list\n",
        self->nick_name,match);

    send_msg_back(connfd,buf);
}

void privmsg_command(int connfd,char *target_list,char* msg){
    user *u = user_table[connfd];
    char buf[MAX_MSG_LEN];
    channel *c;        
    char *target;
    int tar_fd;

    while((target = strsep(&target_list,","))){
        snprintf(buf,MAX_MSG_LEN,":%s PRIVMSG %s:%s\n",u->nick_name, target, msg);
        /* ignore PRIVMSG to self */
        if(!strcasecmp(target,u->nick_name))
            continue;
        /* if target is a valid channal, send the message to its memembers*/
        if(channel_valid(target) && (c = find_channel(target)))
            invoke_channel(connfd,buf,c);
        /* if target is a valid user, send the message to it */
        else if(nick_valid(target) && (tar_fd = find_user(target,connfd)) >= 0)
            send_msg_back(tar_fd,buf);
        /* illegal target should be returned */
        else{
            snprintf(buf,MAX_MSG_LEN,"%s:No such nick/channel\n",target);
            send_msg_back(connfd,buf);
        }          
    }  
}

void invoke_channel(int connfd,char *msg, channel* c){
    fd_list* member;
    if(c)
        for(member=c->member->next;member;member = member->next)
            if(member->fd != connfd)
                send_msg_back(member->fd,msg);
}

/*
 * void init_node( int argc, char *argv[] )
 *
 * Takes care of initializing a node for an IRC server
 * from the given command line arguments
 */
void init_node( int argc, char *argv[] ){
    int i;

    if( argc < 3 ) {
        printf( "%s <nodeID> <config file>\n", argv[0] );
        exit( 0 );
    }

    /* Parse nodeID */
    curr_nodeID = atol( argv[1] );

    /* Store  */
    rt_parse_config_file(argv[0], &curr_node_config_file, argv[2] );

    /* Get config file for this node */
    for( i = 0; i < curr_node_config_file.size; ++i )
        if( curr_node_config_file.entries[i].nodeID == curr_nodeID )
             curr_node_config_entry = &curr_node_config_file.entries[i];

    /* Check to see if nodeID is valid */
    if( !curr_node_config_entry ) {
        printf( "Invalid NodeID\n" );
        exit(1);
    }
}

/*
 * size_t get_msg( char *buf, char *msg )
 *
 * char *buf : the buffer containing the text to be parsed
 * char *msg : a user Malloc'ed buffer to which get_msg will copy the message
 *
 * Copies all the characters from buf[0] up to and including the first instance
 * of the IRC endline characters "\r\n" into msg.  msg should be at least as
 * large as buf to prevent overflow.
 *
 * Returns the size of the message copied to msg.
 */
size_t get_msg(char *buf, char *msg) {
    char *end;
    int  len;

    /* Find end of message */
    end = strstr(buf, "\r\n");

    if( end ) {
        len = end - buf + 2;
    } else {
        /* Could not find \r\n, try searching only for \n */
        end = strstr(buf, "\n");
    	if( end )
            len = end - buf + 1;
    	else
            return -1;
    }

    /* found a complete message */
    memcpy(msg, buf, len);
    msg[end-buf] = '\0';

    return len;
}

/*
 * int tokenize( char const *in_buf, char tokens[MAX_MSG_TOKENS][MAX_MSG_LEN+1] )
 *
 * A strtok() variant.  If in_buf is a space-separated list of words,
 * then on return tokens[X] will contain the Xth word in in_buf.
 *
 * Note: You might want to look at the first word in tokens to
 * determine what action to take next.
 *
 * Returns the number of tokens parsed.
 */
int tokenize( char const *in_buf, char tokens[MAX_MSG_TOKENS][MAX_MSG_LEN+1] ) {
    int i = 0;
    const char *current = in_buf;
    int done = 0;

    /* Possible Bug: handling of too many args */
    while (!done && (i<MAX_MSG_TOKENS)) {
        char *next = strchr(current, ' ');

    	if (next) {
            int temp = next-current;
            if(temp>LIMIT_MSG_LEG)
                temp = LIMIT_MSG_LEG;
    	    memcpy(tokens[i], current, temp);
    	    tokens[i][temp] = '\0';
    	    current = next + 1;   /* move over the space */
    	    ++i;

    	    /* trailing token */
    	    if (*current == ':') {
        	    ++current;
        		strncpy(tokens[i], current,LIMIT_MSG_LEG);
        		++i;
        		done = 1;
    	    }
    	} else {
    	    strncpy(tokens[i], current,LIMIT_MSG_LEG);
    	    ++i;
    	    done = 1;
    	}
    }
    return i - 1;
}

void init_channel_user(){
    header = (channel*) Calloc(1,sizeof(channel));
    footer = (channel*) Calloc(1,sizeof(channel));
    header->next = footer;
    footer->prev = header;

    /* set user table as all NULL */
    int i;
    for (i = 0; i < FD_SETSIZE; ++i)
        user_table[i] = NULL;
}

int find_user(char* name, int connfd){
    int i;
    user *u;
    for (i = 0; i <= p.maxi; i++) {
        u = user_table[p.clientfd[i]];
        if(u && u->nick_name && p.clientfd[i] != connfd && !strcasecmp(name,u->nick_name))
            return p.clientfd[i];
    }
    return -1;
}

/*
 *  Create channel if not exists
 *  return the existing channel or new channel with the name of 'name'
 */
channel* create_channel(char* name){
    if(!name)
        return NULL;

    channel* new_channel;

    if((new_channel = find_channel(name)))
        return new_channel;

    new_channel = (channel*)Malloc(sizeof(channel));
    new_channel->name = strdup(name);
    new_channel->prev = footer->prev;
    new_channel->next = footer;
    new_channel->member = (fd_list*)Calloc(1,sizeof(fd_list)); 

    /* the number of user is stored at header of fd_list*/
    new_channel->prev->next = new_channel;
    footer->prev = new_channel;

    return new_channel;
}

channel* find_channel(char *name){
    channel* temp;
    for(temp = header; temp != footer; temp = temp->next)
        if(temp->name && !strcasecmp(temp->name, name))
            return temp;
    return NULL;
}

void remove_channel(channel* channel){
    channel->prev->next = channel->next;
    channel->next->prev = channel->prev;
    free_channel(channel);
}

void add_fd_list(fd_list* list, int fd){
    fd_list* new = (fd_list*)malloc(sizeof(fd_list));
    new->fd = fd;
    new->next = list->next;
    list->next = new;
    list->fd++;    /* increase the size of the linked list by 1 */
}

int remove_fd_list(fd_list* list, int fd){
    fd_list *temp = list->next;
    fd_list *next;

    /* only one element left */
    if(!list->next->next){
        Free(temp);
        return --(list->fd);        /* decrease the size of the linked list by 1 */
    }

    for(; temp->next->next; temp = temp->next){
        if(fd == temp->fd){
            next = temp->next;
            temp->fd = next->fd;
            temp->next = next->next;
            Free(next);
            return --(list->fd);    /* decrease the size of the linked list by 1 */
        }
    }

    next = temp->next;

    if(fd == temp->fd){
        temp->fd = next->fd;
        temp->next = NULL;
        Free(next);  
        return --(list->fd);        /* decrease the size of the linked list by 1 */
    }
    if(next && fd == next->fd){
        temp->next = NULL;
        Free(next);
        return --(list->fd);        /* decrease the size of the linked list by 1 */
    }
    /* not found, return the size of the linked list */
    return list->fd; 
}

void free_user(user* u){
    if(u){
        if(u->host_name)
            Free(u->host_name);
        if(u->server_name)
            Free(u->server_name);
        if(u->user_name)
            Free(u->user_name);
        if(u->nick_name)
            Free(u->nick_name);
        if(u->real_name)
            Free(u->real_name);
        Free(u);
    }
}

void free_channel(channel* c){
    if(c){
        if(c->name)
            Free(c->name);
        if(c->member)
            Free(c->member);
        Free(c);
    }
}

int show_user(char* result,int max,user* u){
    int length = 0;
    if(u){
        length += snprintf(result + length, max - length, "[user:%s|",u->user_name);
        length += snprintf(result + length, max - length, "server:%s|",u->server_name);
        length += snprintf(result + length, max - length, "host:%s|",u->host_name);
        length += snprintf(result + length, max - length, "nick:%s|",u->nick_name);
        length += snprintf(result + length, max - length, "real:%s]\n",u->real_name);
    }
    return length;
}

int show_channel(char* result, int max,channel* c){
    int length = 0;

    length += snprintf(result + length, max - length, "\t\t[CHANNEL %s(%i)]\n",c->name,c->member->fd);
    if(c->member->fd > 0){
        length += snprintf(result + length, max - length, "\t\t\tMember List:\n");

        fd_list *temp;
        char user[MAX_MSG_LEN];
        for (temp = c->member->next;temp;temp = temp->next){
            show_user(user, MAX_MSG_LEN ,user_table[temp->fd]);
            length += snprintf(result + length, max - length, "\t\t\t%s\n",user);
        }
    }

    return length;
}

void debug_list_all_user(){
    int i, connfd;
    char result[MAX_MSG_LEN];
    //DEBUG
    printf("\t~DEBUG:CURRENT USERS:\n");

    for (i = 0; i <= p.maxi; i++) {
        connfd = p.clientfd[i];
        if(show_user(result,MAX_MSG_LEN, user_table[connfd]))
            printf("\t\tID=%d%s", connfd ,result);
    }
}

void debug_list_all_channel(){
    char result[MAX_MSG_LEN];
    //DEBUG
    printf("\t~DEBUG:CURRENT CHANNELS:\n");

    channel* temp;
    for(temp = header->next; temp->next; temp=temp->next)
        if(show_channel(result,MAX_MSG_LEN, temp))
            printf("%s", result);
}